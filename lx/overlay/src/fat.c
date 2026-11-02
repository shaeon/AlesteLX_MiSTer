/**
 * @file fat.c
 * @brief Ficheros de discos MSX-DOS (FAT12), ver fat.h
 * Shaeon (Carlos Palmero).
 */
#include "fat.h"
#include "drivers/fdc.h"
#include "drivers/dma.h"

static uint8_t  sec[512];
static uint8_t  fatb[9 * 512];      /* la FAT entera (720 KB: 3 sectores) */
static uint8_t  drv, spc, mounted;
static uint16_t root_lba, root_secs, data_lba, nclusters;

static uint16_t le16(const uint8_t* p) { return p[0] | ((uint16_t)p[1] << 8); }

uint8_t fat_mount(uint8_t drive) {
    uint16_t bps, res, spf, rootents, total, i;
    uint8_t nfats;
    mounted = 0;
    drv = drive;
    if (fdc_read_lba(drv, 0, sec)) return FAT_ERR_DISK;
    bps = le16(sec + 11); spc = sec[13]; res = le16(sec + 14); nfats = sec[16];
    rootents = le16(sec + 17); total = le16(sec + 19); spf = le16(sec + 22);
    if (bps != 512 || spc == 0 || nfats == 0 || spf == 0 || spf > 9 || rootents == 0)
        return FAT_ERR_FORMAT;
    for (i = 0; i < spf; i++)
        if (fdc_read_lba(drv, res + i, fatb + i * 512)) return FAT_ERR_DISK;
    root_lba  = res + nfats * spf;
    root_secs = (rootents * 32 + 511) / 512;
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

uint8_t fat_dir(uint8_t (*cb)(const fat_entry_t* e)) {
    uint16_t s;
    uint8_t i;
    fat_entry_t e;
    if (!mounted) return FAT_ERR_FORMAT;
    for (s = 0; s < root_secs; s++) {
        if (fdc_read_lba(drv, root_lba + s, sec)) return FAT_ERR_DISK;
        for (i = 0; i < 16; i++) {
            const uint8_t* d = sec + i * 32;
            if (d[0] == 0) return FAT_OK;
            if (d[0] == 0xE5 || (d[11] & 0x08)) continue;   /* borrado o etiqueta */
            entry_from(d, &e);
            if (cb(&e)) return FAT_OK;
        }
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

uint8_t fat_load(const fat_entry_t* e, uint32_t phys, void (*progress)(uint16_t kb)) {
    uint16_t cl = e->cluster;
    uint32_t left = e->size, done = 0;
    uint32_t buf = dma_phys(sec);
    uint8_t k;
    if (!mounted) return FAT_ERR_FORMAT;
    while (left && cl >= 2 && cl < 0xFF8) {
        uint16_t lba = data_lba + (cl - 2) * spc;
        for (k = 0; k < spc && left; k++) {
            uint16_t n = left > 512 ? 512 : (uint16_t)left;
            if (fdc_read_lba(drv, lba + k, sec)) return FAT_ERR_DISK;
            dma_copy(buf, phys + done, n);
            done += n; left -= n;
            if (progress && !(done & 0x1FFF)) progress(done >> 10);
        }
        cl = next_cluster(cl);
    }
    return left ? FAT_ERR_DISK : FAT_OK;
}

uint16_t fat_free_kb(void) {
    uint16_t cl, n = 0;
    if (!mounted) return 0;
    for (cl = 2; cl < nclusters; cl++) if (next_cluster(cl) == 0) n++;
    return (uint32_t)n * spc / 2;
}
