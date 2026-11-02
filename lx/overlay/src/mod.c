/**
 * @file mod.c
 * @brief Reproductor de MOD de ProTracker por la Magic Sound 2 (ver mod.h)
 * Shaeon (Carlos Palmero).
 *
 * Efectos: 0 arpegio, 1/2 portamento, 3 portamento hacia la nota, 4 vibrato,
 * 5 = 3 + A, 6 = 4 + A, 9 desplazamiento de muestra, A volumen, B salto de
 * posicion, C volumen, D salto de patron, F velocidad/tempo, y E1/E2
 * (portamento fino), EA/EB (volumen fino) y EC (corte de nota). Sin afinacion
 * fina de las muestras. Muestras de hasta 64 KB. Canales 0 y 3 a la
 * izquierda, 1 y 2 a la derecha (con algo de mezcla).
 *
 * Tambien Scream Tracker 2 (STM, como las canciones del reproductor MAG de
 * la MagicSound del Aleste 520EX): mismos patrones de 64 filas x 4 canales x
 * 4 bytes; cada fila se traduce al formato del MOD (nota con la C2SPD del
 * instrumento -> periodo de Amiga, efectos A-J -> F, B, D, A, 2, 1, 3, 4, 0)
 * y la columna de volumen se aplica aparte.
 */
#include "mod.h"
#include "drivers/snd.h"
#include "drivers/dma.h"

#define ROW_BYTES  16
#define PAT_BYTES  1024

typedef struct {
    uint32_t start;
    uint16_t len, loop_s, loop_l;          /* en bytes */
    uint8_t  vol;
} msmp_t;

typedef struct {
    uint8_t  smp;
    uint16_t period, target;
    uint8_t  vol;
    uint8_t  eff, par;
    uint8_t  porta, vib_cmd, vib_pos;
    uint8_t  dirty;                        /* 1 periodo, 2 volumen */
} mch_t;

static uint8_t  hdr[1168];               /* MOD: 1084; STM: 1168 */
static uint8_t  rowbuf[ROW_BYTES];
static msmp_t   smp[32];
static mch_t    chn[4];
static snd_voice_t voice;
static uint32_t pat_base;
static uint8_t  song_len, npat, playing;
static uint8_t  speed, tick, row, pos;
static uint8_t  jump_pos, break_row, do_jump;
static char     title[21];
static uint8_t  fmt;                     /* 0 MOD, 1 STM */
static uint8_t  init_speed;
static uint16_t c2spd[32];               /* STM: Hz de la nota C-2 de cada instrumento */
static uint8_t  stm_vol[4];              /* STM: columna de volumen de la fila (FFh = no) */

static const uint8_t vib_sine[32] = {
    0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
    255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24 };

/* 65536 * 2^(-n/12): periodo de la nota n semitonos por encima */
static const uint16_t semis[16] = {
    65535, 61857, 58385, 55109, 52016, 49097, 46341, 43740,
    41285, 38968, 36781, 34716, 32768, 30929, 29193, 27554 };

static uint16_t be16(const uint8_t* p) { return ((uint16_t)p[0] << 8) | p[1]; }

static uint16_t words_to_bytes(uint16_t w) {
    return w >= 0x8000 ? 0xFFFE : w << 1;
}

static uint16_t le16(const uint8_t* p) { return p[0] | ((uint16_t)p[1] << 8); }

static uint8_t is_stm(void) {
    static const char* const sigs[3] = { "!Scream!", "BMOD2STM", "WUZAMOD!" };
    uint8_t k, i;
    for (k = 0; k < 3; k++) {
        for (i = 0; i < 8 && hdr[20 + i] == (uint8_t)sigs[k][i]; i++) ;
        if (i == 8) return 1;
    }
    return 0;
}

static uint8_t stm_load(uint32_t phys) {
    uint8_t i;
    fmt = 1;
    init_speed = hdr[32] >> 4;
    if (hdr[31] < 10) init_speed = hdr[32] / 10;        /* versiones antiguas */
    if (!init_speed) init_speed = 6;
    npat = hdr[33];
    if (npat == 0 || npat > 64) return MOD_ERR_FORMAT;
    smp[0].len = 0;
    for (i = 0; i < 31; i++) {
        const uint8_t* s = &hdr[48 + 32 * i];
        msmp_t* m = &smp[i + 1];
        uint16_t ls = le16(s + 18), le = le16(s + 20);
        m->start = phys + ((uint32_t)le16(s + 14) << 4);
        m->len   = le16(s + 16);
        m->vol   = s[22] > 64 ? 64 : s[22];
        if (le != 0xFFFF && le > ls && le <= m->len) { m->loop_s = ls; m->loop_l = le - ls; }
        else { m->loop_s = 0; m->loop_l = 0; }
        c2spd[i + 1] = le16(s + 24) ? le16(s + 24) : 8448;
    }
    /* lista de orden (1040, fin en 99 o mas) al sitio de la del MOD (952) */
    song_len = 0;
    while (song_len < 128 && hdr[1040 + song_len] < 99 && hdr[1040 + song_len] < npat) song_len++;
    if (!song_len) song_len = 1;
    for (i = 0; i < 128; i++) hdr[952 + i] = hdr[1040 + i];
    pat_base = phys + 1168;
    return MOD_OK;
}

/* STM: nota (octava * 12 + semitono) con la C2SPD c2 -> periodo de Amiga.
   La nota 24 (C-2) suena a c2 Hz: periodo = 3546895 / c2 / 2^((nota-24)/12) */
static uint16_t stm_period(uint8_t note, uint16_t c2) {
    int8_t d = (int8_t)note - 24, q = 0;
    uint32_t p;
    while (d < 0) { d += 12; q--; }
    while (d >= 12) { d -= 12; q++; }
    p = (3546895UL * 16) / c2;
    p = (p * semis[d]) >> 16;
    if (q > 0) p >>= q; else if (q < 0) p <<= -q;
    p >>= 4;
    if (p > 0xFFF) p = 0xFFF;
    if (p < 57) p = 57;
    return (uint16_t)p;
}

/* STM: traduce la fila de rowbuf al formato del MOD */
static void stm_row(void) {
    uint8_t c;
    for (c = 0; c < 4; c++) {
        uint8_t* n = &rowbuf[c * 4];
        uint8_t b0 = n[0], ins = n[1] >> 3;
        uint8_t vol = (n[1] & 7) | ((n[2] & 0xF0) >> 1);
        uint8_t cmd = n[2] & 0x0F, par = n[3], e = 0;
        uint16_t per = 0;
        if (ins > 31) ins = 0;
        if (b0 < 0xFB) {
            uint8_t sm = ins ? ins : chn[c].smp;
            per = stm_period((b0 >> 4) * 12 + (b0 & 15), sm ? c2spd[sm] : 8448);
        }
        stm_vol[c] = vol <= 64 ? vol : 0xFF;
        if (b0 == 0xFE) stm_vol[c] = 0;                  /* corte de nota */
        switch (cmd) {
        case 1:  e = 0xF; par >>= 4; if (!par) e = 0; break; /* A velocidad */
        case 2:  e = 0xB; break;                          /* B salto de posicion */
        case 3:  e = 0xD; break;                          /* C salto de patron */
        case 4:  e = 0xA; break;                          /* D volumen */
        case 5:  e = 0x2; break;                          /* E portamento abajo */
        case 6:  e = 0x1; break;                          /* F portamento arriba */
        case 7:  e = 0x3; break;                          /* G portamento a la nota */
        case 8:  e = 0x4; break;                          /* H vibrato */
        case 10: e = 0x0; break;                          /* J arpegio */
        default: e = 0; par = 0;                          /* I y el resto: nada */
        }
        n[0] = (ins & 0xF0) | ((per >> 8) & 0x0F);
        n[1] = (uint8_t)per;
        n[2] = ((ins & 0x0F) << 4) | e;
        n[3] = par;
    }
}

uint8_t mod_load(uint32_t phys) {
    uint8_t i, sig_ok;
    uint32_t a;
    mod_stop();
    dma_copy(phys, dma_phys(hdr), sizeof(hdr));
    for (i = 0; i < 20; i++) title[i] = (hdr[i] >= 0x20 && hdr[i] < 0x7F) ? hdr[i] : (hdr[i] ? '?' : 0);
    title[20] = 0;
    if (is_stm()) return stm_load(phys);
    fmt = 0;
    init_speed = 6;
    sig_ok = (hdr[1080] == 'M' && hdr[1081] == '.' && hdr[1082] == 'K' && hdr[1083] == '.') ||
             (hdr[1080] == 'M' && hdr[1081] == '!' && hdr[1082] == 'K' && hdr[1083] == '!') ||
             (hdr[1080] == '4' && hdr[1081] == 'C' && hdr[1082] == 'H' && hdr[1083] == 'N') ||
             (hdr[1080] == 'F' && hdr[1081] == 'L' && hdr[1082] == 'T' && hdr[1083] == '4');
    if (!sig_ok) return MOD_ERR_FORMAT;
    song_len = hdr[950];
    if (song_len == 0 || song_len > 128) song_len = 1;
    npat = 0;
    for (i = 0; i < 128; i++) if (hdr[952 + i] >= npat) npat = hdr[952 + i] + 1;
    pat_base = phys + 1084;
    a = pat_base + (uint32_t)npat * PAT_BYTES;
    smp[0].len = 0;
    for (i = 0; i < 31; i++) {
        const uint8_t* s = &hdr[20 + 30 * i];
        msmp_t* m = &smp[i + 1];
        uint16_t lw = be16(s + 22);
        m->start  = a;
        m->len    = words_to_bytes(lw);
        m->vol    = s[25] > 64 ? 64 : s[25];
        m->loop_s = words_to_bytes(be16(s + 26));
        m->loop_l = words_to_bytes(be16(s + 28));
        if ((uint32_t)m->loop_s + m->loop_l > m->len) m->loop_l = 0;
        a += (uint32_t)lw << 1;
    }
    return MOD_OK;
}

/* ---- salida al driver */
static void out_volume(uint8_t c) {
    uint16_t v = (uint16_t)chn[c].vol << 2;
    uint8_t main, other;
    if (v > 255) v = 255;
    main = (uint8_t)v;
    other = main >> 2;
    if (c == 0 || c == 3) snd_set_volume(c, main, other);
    else                  snd_set_volume(c, other, main);
}

static void out_period(uint8_t c, uint16_t period) {
    if (period < 113) period = 113;
    if (period > 856 * 2) period = 856 * 2;
    snd_set_step(c, snd_step_period(period));
}

static void put24(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16);
}

/* Hace sonar la muestra del canal desde 'offset' con el periodo del canal */
static void trigger(uint8_t c, uint16_t offset) {
    msmp_t* m = &smp[chn[c].smp];
    uint32_t st;
    if (!chn[c].smp || m->len < 2 || offset >= m->len) { snd_stop(c); return; }
    voice.channel = c;
    put24(voice.start, m->start + offset);
    if (m->loop_l > 2) {
        voice.flags = SND_LOOP;
        put24(voice.loop, m->start + m->loop_s);
        put24(voice.end,  m->start + m->loop_s + m->loop_l);
        if (offset >= m->loop_s + m->loop_l) put24(voice.start, m->start + m->loop_s);
    } else {
        voice.flags = 0;
        put24(voice.loop, m->start);
        put24(voice.end,  m->start + m->len);
    }
    voice.vol_l = 0; voice.vol_r = 0;            /* lo pone out_volume despues */
    st = snd_step_period(chn[c].period);
    put24(voice.step, st);
    snd_play(&voice);
    chn[c].dirty |= 2;
}

/* ---- efectos */
static void vol_slide(mch_t* ch, uint8_t par) {
    uint8_t up = par >> 4, dn = par & 15;
    if (up) { ch->vol += up; if (ch->vol > 64) ch->vol = 64; }
    else if (ch->vol > dn) ch->vol -= dn; else ch->vol = 0;
    ch->dirty |= 2;
}

static void tone_porta(mch_t* ch) {
    if (!ch->target) return;
    if (ch->period < ch->target) {
        ch->period += ch->porta;
        if (ch->period > ch->target) ch->period = ch->target;
    } else if (ch->period > ch->target) {
        if (ch->period > ch->target + ch->porta) ch->period -= ch->porta;
        else ch->period = ch->target;
    }
    ch->dirty |= 1;
}

static int16_t vibrato(mch_t* ch) {
    int16_t d = ((int16_t)vib_sine[ch->vib_pos & 31] * (ch->vib_cmd & 15)) >> 7;
    if (ch->vib_pos & 32) d = -d;
    ch->vib_pos = (ch->vib_pos + (ch->vib_cmd >> 4)) & 63;
    return d;
}

static void do_row(void) {
    uint8_t c;
    uint32_t a = pat_base + (uint32_t)hdr[952 + pos] * PAT_BYTES + (uint16_t)row * ROW_BYTES;
    dma_copy(a, dma_phys(rowbuf), ROW_BYTES);
    if (fmt) stm_row();
    for (c = 0; c < 4; c++) {
        const uint8_t* n = &rowbuf[c * 4];
        mch_t* ch = &chn[c];
        uint8_t  s = (n[0] & 0xF0) | (n[2] >> 4);
        uint16_t p = ((uint16_t)(n[0] & 0x0F) << 8) | n[1];
        uint8_t  e = n[2] & 0x0F, par = n[3];
        uint16_t offset = 0;
        ch->eff = e; ch->par = par;
        if (s && s < 32) { ch->smp = s; ch->vol = smp[s].vol; ch->dirty |= 2; }
        if (fmt && stm_vol[c] != 0xFF) { ch->vol = stm_vol[c]; ch->dirty |= 2; }
        if (e == 9 && p) offset = (uint16_t)par << 8;
        if (p) {
            if (e == 3 || e == 5) ch->target = p;
            else { ch->period = p; ch->vib_pos = 0; trigger(c, offset); }
        }
        switch (e) {
        case 0x3: if (par) ch->porta = par; break;
        case 0x4: if (par & 0x0F) ch->vib_cmd = (ch->vib_cmd & 0xF0) | (par & 0x0F);
                  if (par & 0xF0) ch->vib_cmd = (ch->vib_cmd & 0x0F) | (par & 0xF0); break;
        case 0xB: jump_pos = par; break_row = 0; do_jump = 1; break;
        case 0xC: ch->vol = par > 64 ? 64 : par; ch->dirty |= 2; break;
        case 0xD: if (!do_jump) jump_pos = pos + 1;
                  break_row = (par >> 4) * 10 + (par & 15); if (break_row > 63) break_row = 0;
                  do_jump = 1; break;
        case 0xE:
            switch (par >> 4) {
            case 0x1: if (ch->period > 113 + (par & 15)) ch->period -= par & 15; ch->dirty |= 1; break;
            case 0x2: ch->period += par & 15; ch->dirty |= 1; break;
            case 0xA: vol_slide(ch, (par & 15) << 4); break;
            case 0xB: vol_slide(ch, par & 15); break;
            case 0xC: if ((par & 15) == 0) { ch->vol = 0; ch->dirty |= 2; } break;
            }
            break;
        case 0xF:
            if (par == 0) break;
            if (par < 32) speed = par;
            else snd_set_timer_period((uint16_t)(120000UL / par));   /* 2,5 s / BPM a 48 kHz */
            break;
        }
    }
}

static void do_tick(void) {
    uint8_t c;
    for (c = 0; c < 4; c++) {
        mch_t* ch = &chn[c];
        uint8_t par = ch->par;
        switch (ch->eff) {
        case 0x0:
            if (par) {
                uint8_t k = tick % 3;
                uint8_t n = k == 0 ? 0 : (k == 1 ? par >> 4 : par & 15);
                out_period(c, (uint16_t)(((uint32_t)ch->period * semis[n]) >> 16));
            }
            break;
        case 0x1: if (ch->period > 113 + par) ch->period -= par; else ch->period = 113; ch->dirty |= 1; break;
        case 0x2: ch->period += par; if (ch->period > 856 * 2) ch->period = 856 * 2; ch->dirty |= 1; break;
        case 0x3: tone_porta(ch); break;
        case 0x4: out_period(c, ch->period + vibrato(ch)); break;
        case 0x5: tone_porta(ch); vol_slide(ch, par); break;
        case 0x6: out_period(c, ch->period + vibrato(ch)); vol_slide(ch, par); break;
        case 0xA: vol_slide(ch, par); break;
        case 0xE:
            if ((par >> 4) == 0xC && (par & 15) == tick) { ch->vol = 0; ch->dirty |= 2; }
            break;
        }
    }
}

static void player_isr(void) {
    uint8_t c;
    if (tick == 0) do_row(); else do_tick();
    for (c = 0; c < 4; c++) {
        if (chn[c].dirty & 1) out_period(c, chn[c].period);
        if (chn[c].dirty & 2) out_volume(c);
        chn[c].dirty = 0;
    }
    if (++tick >= speed) {
        tick = 0;
        if (do_jump) {
            do_jump = 0;
            pos = jump_pos;
            row = break_row;
        } else if (++row >= 64) {
            row = 0;
            pos++;
        }
        if (pos >= song_len) pos = 0;
    }
}

void mod_play(void) {
    uint8_t c;
    mod_stop();
    for (c = 0; c < 4; c++) {
        chn[c].smp = 0; chn[c].period = 0; chn[c].target = 0; chn[c].vol = 0;
        chn[c].eff = 0; chn[c].par = 0; chn[c].porta = 0; chn[c].vib_cmd = 0;
        chn[c].vib_pos = 0; chn[c].dirty = 0;
    }
    speed = init_speed; tick = 0; row = 0; pos = 0; do_jump = 0;
    snd_master(255, 255);
    playing = 1;
    snd_set_timer(960, player_isr);           /* 125 BPM: 50 Hz */
}

void mod_stop(void) {
    uint8_t c;
    if (!playing) return;
    playing = 0;
    snd_set_timer(0, 0);
    for (c = 0; c < 4; c++) snd_stop(c);
}

uint8_t     mod_playing(void)  { return playing; }
const char* mod_title(void)    { return title; }
uint8_t     mod_position(void) { return pos; }
uint8_t     mod_length(void)   { return song_len; }
uint8_t     mod_row(void)      { return row; }
uint8_t     mod_patterns(void) { return npat; }
const char* mod_kind(void)     { return fmt ? "STM" : "MOD"; }
