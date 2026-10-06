// Host test for BpmCore: feeds a 16 bit PCM WAV file through the detector as
// the app would, and prints every 2 s result. Not part of the app package.
// build: see tools/README
#include "../src/BpmCore.h"
#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

int main(int argc, char **argv)
{
    if (argc < 2) { std::fprintf(stderr, "usage: bpmtest <file.wav> [silenceRms]\n"); return 2; }
    FILE *f = std::fopen(argv[1], "rb");
    if (!f) { std::perror(argv[1]); return 1; }
    char hdr[12]; if (std::fread(hdr, 1, 12, f) != 12 || std::memcmp(hdr, "RIFF", 4)) return 1;
    uint16_t ch = 0, bits = 0; uint32_t rate = 0, dataLen = 0;
    for (;;) {
        char id[4]; uint32_t len;
        if (std::fread(id, 1, 4, f) != 4 || std::fread(&len, 4, 1, f) != 1) return 1;
        if (!std::memcmp(id, "fmt ", 4)) {
            std::vector<char> b(len); if (std::fread(b.data(), 1, len, f) != len) return 1;
            std::memcpy(&ch, &b[2], 2); std::memcpy(&rate, &b[4], 4); std::memcpy(&bits, &b[14], 2);
        } else if (!std::memcmp(id, "data", 4)) { dataLen = len; break; }
        else std::fseek(f, len, SEEK_CUR);
    }
    if (bits != 16) { std::fprintf(stderr, "16 bit only\n"); return 1; }
    BpmCore core(rate);
    if (argc > 2) core.setSilenceRms(float(atof(argv[2])));
    std::vector<int16_t> buf(BpmCore::HOP * ch);
    std::vector<float> mono(BpmCore::HOP);
    uint64_t frames = 0;
    while (std::fread(buf.data(), sizeof(int16_t), buf.size(), f) == buf.size()) {
        double sq = 0;
        for (unsigned i = 0; i < BpmCore::HOP; ++i) {
            double m = 0;
            for (unsigned c = 0; c < ch; ++c) { double s = buf[i * ch + c]; sq += s * s; m += s; }
            mono[i] = float(m / ch / 32768.0);
        }
        const float rms = float(std::sqrt(sq / (BpmCore::HOP * ch)));
        frames += BpmCore::HOP;
        core.feed(mono.data(), rms, double(frames) / rate);
        if (core.emitted())
            std::printf("%6.1f s  bpm %3d  confidence %3d\n", double(frames) / rate, core.bpm(), core.confidence());
    }
    (void)dataLen;
    return 0;
}
