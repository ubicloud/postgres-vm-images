// Runs when the data disk is hot-plugged into a clone restored from a
// template: every clone starts with the template's CRNG state and wall clock,
// so reseed from the host's virtio-rng and set the clock from the host's
// ptp_kvm before anything that needs either (fsck, mount, PostgreSQL) starts.
#include <fcntl.h>
#include <linux/random.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#define FD_TO_CLOCKID(fd) ((~(clockid_t)(fd) << 3) | 3)

static int reseed(void) {
  struct { int entropy_count; int buf_size; unsigned char buf[64]; } p;
  int h = open("/dev/hwrng", O_RDONLY);
  if (h < 0) { perror("open /dev/hwrng"); return -1; }
  size_t got = 0;
  while (got < sizeof p.buf) {
    ssize_t n = read(h, p.buf + got, sizeof p.buf - got);
    if (n <= 0) { perror("read /dev/hwrng"); close(h); return -1; }
    got += n;
  }
  close(h);
  p.entropy_count = sizeof p.buf * 8;
  p.buf_size = sizeof p.buf;
  int r = open("/dev/urandom", O_WRONLY);
  if (r < 0) { perror("open /dev/urandom"); return -1; }
  if (ioctl(r, RNDADDENTROPY, &p) < 0) { perror("RNDADDENTROPY"); close(r); return -1; }
  if (ioctl(r, RNDRESEEDCRNG) < 0) { perror("RNDRESEEDCRNG"); close(r); return -1; }
  close(r);
  return 0;
}

static int set_clock(double *step) {
  int fd = open("/dev/ptp0", O_RDONLY);
  if (fd < 0) { perror("open /dev/ptp0"); return -1; }
  struct timespec host, guest;
  clock_gettime(CLOCK_REALTIME, &guest);
  if (clock_gettime(FD_TO_CLOCKID(fd), &host) < 0) { perror("ptp gettime"); close(fd); return -1; }
  close(fd);
  *step = (host.tv_sec - guest.tv_sec) + (host.tv_nsec - guest.tv_nsec) / 1e9;
  if (clock_settime(CLOCK_REALTIME, &host) < 0) { perror("clock_settime"); return -1; }
  return 0;
}

// --no-reseed only sets the clock: the negative control for measuring how
// random restored clones are without the reseed.
int main(int argc, char **argv) {
  struct timespec t0, t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  int rc = 0;
  if (!(argc > 1 && strcmp(argv[1], "--no-reseed") == 0) && reseed() < 0) rc = 1;
  double step = 0;
  if (set_clock(&step) < 0) rc = 1;
  clock_gettime(CLOCK_MONOTONIC, &t1);
  fprintf(stderr, "cell-restore-hook: clock stepped %.3f s, took %.3f ms\n", step,
          (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6);
  return rc;
}
