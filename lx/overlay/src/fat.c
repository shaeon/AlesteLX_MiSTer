/**
 * @file fat.c
 * @brief Ficheros de discos MSX-DOS (FAT12), ver fat.h
 * Shaeon (Carlos Palmero).
 *
 * Un sector en cache (sec, con su lba y si esta modificado) por el que pasan
 * el directorio y las lecturas y escrituras sueltas; los ficheros enteros se
 * cargan por pistas (read_run). Con FAT_WRITE (el LX-DOS) tambien se escribe:
 * la FAT esta en memoria y fat_sync la escribe en todas sus copias.
 */
#include "fat.h"
#include "drivers/fdc.h"
#include "drivers/dma.h"

static uint8_t  sec[512];
static uint16_t sec_lba = 0xFFFF;
static uint8_t  sec_dirty;
static uint8_t  fatb[9 * 512];      /* la FAT entera (720 KB: 3 sectores) */
static uint8_t  drv, spc, mounted, nfats, fat_dirty;
static uint16_t res_secs, spf, root_ents;
static uint16_t root_lba, root_secs, data_lba, nclusters;

static uint16_t le16(const uint8_t* p) { return p[0] | ((uint16_t)p[1] << 8); }

/* ---- cache de sector */
static uint8_t cache_flush(void) {
#ifdef FAT_WRITE
    if (sec_dirty) {
        if (fdc_write_lba(drv, sec_lba, sec)) return FAT_ERR_DISK;
        sec_dirty = 0;
    }
#endif
    return FAT_OK;
}

static uint8_t cache_get(uint16_t lba) {
    if (lba == sec_lba) return FAT_OK;
    if (cache_flush()) return FAT_ERR_DISK;
    sec_lba = 0xFFFF;
    if (fdc_read_lba(drv, lba, sec)) return FAT_ERR_DISK;
    sec_lba = lba;
    return FAT_OK;
}

uint8_t fat_mount(uint8_t drive) {
    uint16_t total, i;
#ifdef FAT_WRITE
    if (mounted) fat_sync();
#endif
    mounted = 0;
    sec_lba = 0xFFFF; sec_dirty = 0; fat_dirty = 0;
    drv = drive;
    if (cache_get(0)) return FAT_ERR_DISK;
    spc = sec[13]; res_secs = le16(sec + 14); nfats = sec[16];
    root_ents = le16(sec + 17); total = le16(sec + 19); spf = le16(sec + 22);
    if (le16(sec + 11) != 512 || spc == 0 || nfats == 0 || spf == 0 || spf > 9 || root_ents == 0)
        return FAT_ERR_FORMAT;
    for (i = 0; i < spf; i++)
        if (fdc_read_lba(drv, res_secs + i, fatb + i * 512)) return FAT_ERR_DISK;
    root_lba  = res_secs + nfats * spf;
    root_secs = (root_ents * 32 + 511) / 512;
    data_lba  = root_lba + root_secs;
    nclusters = (total - data_lba) / spc + 2;
    mounted = 1;
    return FAT_OK;
}

static uint16_t next_cluster(uint16_t cl) {
    uint16_t i = cl + (cl >> 1);
    uint16_t v = fatb[i] | ((uint16_t)fatb[i + 1] << 8);
    return (cl & 1) ? (v >> 4) : (v & 0x0FFF);
}

static void entry_from(const uint8_t* d, fat_entry_t* e) {
    uint8_t i, n = 0;
    for (i = 0; i < 8 && d[i] != ' '; i++) e->name[n++] = d[i];
    if (d[8] != ' ') {
        e->name[n++] = '.';
        for (i = 8; i < 11 && d[i] != ' '; i++) e->name[n++] = d[i];
    }
    e->name[n] = 0;
    e->attr = d[11];
    e->cluster = le16(d + 26);
    e->size = le16(d + 28) | ((uint32_t)le16(d + 30) << 16);
}

/* Entrada idx del directorio raiz en la cache -> puntero (0 si no se lee) */
static uint8_t* dir_entry(uint16_t idx) {
    if (idx >= root_ents) return 0;
    if (cache_get(root_lba + (idx >> 4))) return 0;
    return sec + (idx & 15) * 32;
}

uint8_t fat_dir(uint8_t (*cb)(const fat_entry_t* e)) {
    uint16_t i;
    fat_entry_t e;
    if (!mounted) return FAT_ERR_FORMAT;
    for (i = 0; i < root_ents; i++) {
        const uint8_t* d = dir_entry(i);
        if (!d) return FAT_ERR_DISK;
        if (d[0] == 0) return FAT_OK;
        if (d[0] == 0xE5 || (d[11] & 0x08)) continue;       /* borrado o etiqueta */
        entry_from(d, &e);
        if (cb(&e)) return FAT_OK;
    }
    return FAT_OK;
}

static const char* find_name;
static fat_entry_t* find_out;
static uint8_t find_ok;

static uint8_t up(uint8_t c) { return (c >= 'a' && c <= 'z') ? c - 32 : c; }

static uint8_t find_cb(const fat_entry_t* e) {
    const char* a = find_name;
    const char* b = e->name;
    while (*a && up(*a) == *b) { a++; b++; }
    if (*a == 0 && *b == 0) { *find_out = *e; find_ok = 1; return 1; }
    return 0;
}

uint8_t fat_find(const char* name, fat_entry_t* e) {
    uint8_t r;
    find_name = name; find_out = e; find_ok = 0;
    r = fat_dir(find_cb);
    if (r) return r;
    return find_ok ? FAT_OK : FAT_ERR_NOFILE;
}

/* Bufer de pista: la DMA lo lleva luego a su sitio */
static uint8_t trk[9 * 512];

/* Lee n sectores desde lba (pueden cruzar pistas) y los deja en phys */
static uint8_t read_run(uint16_t lba, uint16_t n, uint32_t phys, uint32_t* left) {
    if (cache_flush()) return FAT_ERR_DISK;           /* lo que se lee, al dia */
    while (n && *left) {
        uint8_t track = lba / (FDC_SPT * FDC_HEADS);
        uint8_t rest  = lba % (FDC_SPT * FDC_HEADS);
        uint8_t head  = rest >= FDC_SPT;
        uint8_t sidx  = head ? rest - FDC_SPT : rest;
        uint8_t cnt   = FDC_SPT - sidx;                  /* hasta el final de la pista */
        uint8_t r, tries;
        uint16_t bytes;
        if (cnt > n) cnt = n;
        for (tries = 0; tries < 3; tries++) {
            r = fdc_read_multi(drv, track, head, sidx + 1, cnt, trk);
            if (!r) break;
        }
        if (r) return FAT_ERR_DISK;
        bytes = (uint16_t)cnt * 512;
        if (bytes > *left) bytes = (uint16_t)*left;
        dma_copy(dma_phys(trk), phys, bytes);
        phys += bytes; *left -= bytes;
        lba += cnt; n -= cnt;
    }
    return FAT_OK;
}

uint8_t fat_load(const fat_entry_t* e, uint32_t phys, void (*progress)(uint16_t kb)) {
    uint16_t cl = e->cluster;
    uint32_t left = e->size, done;
    if (!mounted) return FAT_ERR_FORMAT;
    while (left && cl >= 2 && cl < 0xFF8) {
        /* tramo de clusteres seguidos */
        uint16_t first = cl, n = 1, nx;
        while ((nx = next_cluster(cl)) == cl + 1 && n < 64) { cl = nx; n++; }
        done = e->size - left;
        if (read_run(data_lba + (first - 2) * spc, n * spc, phys + done, &left)) return FAT_ERR_DISK;
        if (progress) progress((uint16_t)((e->size - left) >> 10));
        cl = next_cluster(cl);
    }
    return left ? FAT_ERR_DISK : FAT_OK;
}

uint8_t fat_read_at(uint16_t cl0, uint32_t off, uint16_t len, uint32_t phys) {
#ifdef FAT_WRITE
    return fat_io(&cl0, off, len, phys, 0);
#else
    uint16_t cbytes = (uint16_t)spc * 512, cl = cl0;
    if (!mounted) return FAT_ERR_FORMAT;
    while (off >= cbytes) {
        cl = next_cluster(cl);
        if (cl < 2 || cl >= 0xFF8) return FAT_ERR_DISK;
        off -= cbytes;
    }
    while (len) {
        uint16_t in = (uint16_t)off;
        uint16_t so = in & 511, n = 512 - so;
        if (n > len) n = len;
        if (cache_get(data_lba + (cl - 2) * spc + (in >> 9))) return FAT_ERR_DISK;
        dma_copy(dma_phys(sec) + so, phys, n);
        phys += n; len -= n; off += n;
        if (off >= cbytes) {
            off -= cbytes;
            cl = next_cluster(cl);
            if (len && (cl < 2 || cl >= 0xFF8)) return FAT_ERR_DISK;
        }
    }
    return FAT_OK;
#endif
}

uint16_t fat_free_kb(void) {
    uint16_t cl, n = 0;
    if (!mounted) return 0;
    for (cl = 2; cl < nclusters; cl++) if (next_cluster(cl) == 0) n++;
    return (uint32_t)n * spc / 2;
}

#ifdef FAT_WRITE
/* ======================================================================
   Escritura (LX-DOS)
   ====================================================================== */

uint8_t fat_use(uint8_t drive) {
    if (mounted && drv == drive) return FAT_OK;
    return fat_mount(drive);
}

void fat_invalidate(void) {
    fat_sync();
    mounted = 0;
}

uint8_t fat_sync(void) {
    uint8_t f;
    uint16_t i;
    if (!mounted) return FAT_OK;
    if (cache_flush()) return FAT_ERR_DISK;
    if (fat_dirty) {
        for (f = 0; f < nfats; f++)
            for (i = 0; i < spf; i++)
                if (fdc_write_lba(drv, res_secs + f * spf + i, fatb + i * 512)) return FAT_ERR_DISK;
        fat_dirty = 0;
    }
    return FAT_OK;
}

static void set_cluster(uint16_t cl, uint16_t v) {
    uint16_t i = cl + (cl >> 1);
    if (cl & 1) {
        fatb[i]     = (fatb[i] & 0x0F) | (uint8_t)(v << 4);
        fatb[i + 1] = (uint8_t)(v >> 4);
    } else {
        fatb[i]     = (uint8_t)v;
        fatb[i + 1] = (fatb[i + 1] & 0xF0) | ((v >> 8) & 0x0F);
    }
    fat_dirty = 1;
}

/* Un cluster libre, marcado como ultimo de su cadena (0 si el disco esta lleno) */
static uint16_t alloc_cluster(void) {
    uint16_t cl;
    for (cl = 2; cl < nclusters; cl++)
        if (next_cluster(cl) == 0) { set_cluster(cl, 0xFFF); return cl; }
    return 0;
}

static void free_chain(uint16_t cl) {
    while (cl >= 2 && cl < 0xFF8) {
        uint16_t nx = next_cluster(cl);
        set_cluster(cl, 0);
        cl = nx;
    }
}

uint8_t fat_io(uint16_t* cl0, uint32_t off, uint16_t len, uint32_t phys, uint8_t write) {
    uint16_t cbytes = (uint16_t)spc * 512, cl;
    if (!mounted) return FAT_ERR_FORMAT;
    if (*cl0 < 2) {
        if (!write) return FAT_ERR_EOF;
        if (!(*cl0 = alloc_cluster())) return FAT_ERR_FULL;
    }
    cl = *cl0;
    while (off >= cbytes) {
        uint16_t nx = next_cluster(cl);
        if (nx < 2 || nx >= 0xFF8) {
            if (!write) return FAT_ERR_EOF;
            if (!(nx = alloc_cluster())) return FAT_ERR_FULL;
            set_cluster(cl, nx);
        }
        cl = nx;
        off -= cbytes;
    }
    while (len) {
        uint16_t in = (uint16_t)off;
        uint16_t so = in & 511, n = 512 - so;
        if (n > len) n = len;
        if (cache_get(data_lba + (cl - 2) * spc + (in >> 9))) return FAT_ERR_DISK;
        if (write) { dma_copy(phys, dma_phys(sec) + so, n); sec_dirty = 1; }
        else       dma_copy(dma_phys(sec) + so, phys, n);
        phys += n; len -= n; off += n;
        if (off >= cbytes && len) {
            uint16_t nx = next_cluster(cl);
            off -= cbytes;
            if (nx < 2 || nx >= 0xFF8) {
                if (!write) return FAT_ERR_EOF;
                if (!(nx = alloc_cluster())) return FAT_ERR_FULL;
                set_cluster(cl, nx);
            }
            cl = nx;
        }
    }
    return FAT_OK;
}

/* ---- directorio con nombres de 11 caracteres ('?' = cualquiera) */
static uint8_t match11(const uint8_t* pat, const uint8_t* name) {
    uint8_t i;
    for (i = 0; i < 11; i++)
        if (pat[i] != '?' && up(pat[i]) != name[i]) return 0;
    return 1;
}

int16_t fat_find11(const uint8_t* pat, int16_t from, uint8_t* ent) {
    uint16_t i;
    if (!mounted) return -1;
    for (i = from < 0 ? 0 : from; i < root_ents; i++) {
        uint8_t* d = dir_entry(i);
        if (!d || d[0] == 0) return -1;
        if (d[0] == 0xE5 || (d[11] & 0x18)) continue;       /* borrado, etiqueta o carpeta */
        if (match11(pat, d)) {
            if (ent) { uint8_t k; for (k = 0; k < 32; k++) ent[k] = d[k]; }
            return i;
        }
    }
    return -1;
}

int16_t fat_create11(const uint8_t* name) {
    uint16_t i;
    uint8_t k;
    if (!mounted) return -1;
    for (i = 0; i < root_ents; i++) {
        uint8_t* d = dir_entry(i);
        if (!d) return -1;
        if (d[0] == 0 || d[0] == 0xE5) {
            for (k = 0; k < 11; k++) d[k] = up(name[k]);
            for (k = 11; k < 32; k++) d[k] = 0;
            d[11] = 0x20;                                     /* archivo */
            d[24] = 0x21; d[25] = 0x5C;                       /* fecha: 1-1-2026 */
            sec_dirty = 1;
            return i;
        }
    }
    return -1;
}

uint8_t fat_set_entry(int16_t idx, uint16_t cl, uint32_t size) {
    uint8_t* d = dir_entry(idx);
    if (!d) return FAT_ERR_DISK;
    d[26] = (uint8_t)cl; d[27] = cl >> 8;
    d[28] = (uint8_t)size; d[29] = (uint8_t)(size >> 8);
    d[30] = (uint8_t)(size >> 16); d[31] = (uint8_t)(size >> 24);
    sec_dirty = 1;
    return FAT_OK;
}

uint8_t fat_delete_idx(int16_t idx) {
    uint8_t* d = dir_entry(idx);
    if (!d) return FAT_ERR_DISK;
    d[0] = 0xE5;
    sec_dirty = 1;
    free_chain(le16(d + 26));
    return FAT_OK;
}

uint8_t fat_rename_idx(int16_t idx, const uint8_t* name) {
    uint8_t k;
    uint8_t* d = dir_entry(idx);
    if (!d) return FAT_ERR_DISK;
    for (k = 0; k < 11; k++) d[k] = up(name[k]);
    sec_dirty = 1;
    return FAT_OK;
}

/* "nombre.ext" -> 11 caracteres con espacios; 1 si tiene comodines */
uint8_t fat_name11(const char* s, uint8_t* n11) {
    uint8_t i, w = 0;
    for (i = 0; i < 11; i++) n11[i] = ' ';
    for (i = 0; *s && *s != '.' && *s != ' '; s++) {
        if (*s == '*') { while (i < 8) n11[i++] = '?'; w = 1; continue; }
        if (i < 8) { n11[i++] = up(*s); if (*s == '?') w = 1; }
    }
    if (*s == '.') for (s++, i = 8; *s && *s != ' '; s++) {
        if (*s == '*') { while (i < 11) n11[i++] = '?'; w = 1; continue; }
        if (i < 11) { n11[i++] = up(*s); if (*s == '?') w = 1; }
    }
    return w;
}
#endif
