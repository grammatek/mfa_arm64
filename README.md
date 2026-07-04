# Montreal Forced Aligner for linux-aarch64

[![Docker Hub](https://img.shields.io/docker/v/lumpidu/mfa-aarch64?sort=semver&label=Docker%20Hub&logo=docker&color=2496ED)](https://hub.docker.com/r/lumpidu/mfa-aarch64)
[![Image size](https://img.shields.io/docker/image-size/lumpidu/mfa-aarch64/latest?label=image%20size)](https://hub.docker.com/r/lumpidu/mfa-aarch64/tags)

A self-contained Docker build of [Montreal Forced Aligner](https://montreal-forced-aligner.readthedocs.io/) 3.3.9 for **linux-aarch64** such as the NVIDIA DGX Spark, Apple Silicon, Ampere and AWS Graviton. conda-forge publishes MFA only where all of its native dependencies have aarch64 builds, and four of them do not, so `mamba install montreal-forced-aligner` fails on ARM Linux out of the box. This image supplies those four itself - three built from source into a local channel, sox from apt - and resolves the rest from conda-forge normally.

> **Unofficial build.** A community packaging for aarch64, not affiliated with or endorsed by the Montreal Forced Aligner project or its authors.

## Usage

Pull the prebuilt image from Docker Hub. It is an arm64 image; on a non-arm host add `--platform linux/arm64` to run it under QEMU.

```bash
docker pull lumpidu/mfa-aarch64
```

Or build it yourself:

```bash
# 1. Fetch the OpenGrm source tarballs. They are SHA-256 verified.
./fetch-sources.sh

# 2a. Build natively on arm64:
docker build -t lumpidu/mfa-aarch64 .
# 2b. or cross-build from an amd64 host under QEMU, which is slower; the kalpy compile alone takes about an hour.
docker buildx build --platform linux/arm64 -t lumpidu/mfa-aarch64 --load .
```

Align a corpus against a pronunciation dictionary and acoustic model. This assumes the current host directory holds:

- `corpus/` - speaker subfolders of audio, each file paired with a `.lab` transcript
- `corpus.dict` - the pronunciation dictionary
- `acoustic.zip` - the acoustic model

`-v "$PWD:/data"` mounts that directory at `/data`, so the `/data/...` arguments resolve to these local files and the alignment is written back to `./out`. `--user` keeps the output owned by you, and `MFA_ROOT_DIR` and `HOME` point at the writable mount.

```bash
docker run --rm -v "$PWD:/data" \
  -e MFA_ROOT_DIR=/data/mfa_root -e HOME=/data \
  --user "$(id -u):$(id -g)" \
  lumpidu/mfa-aarch64 \
  align /data/corpus /data/corpus.dict /data/acoustic.zip /data/out \
  -j "$(nproc)" --clean --output_format json
```

The entrypoint is `mfa`, so any `mfa` subcommand works.

## The four gaps

conda-forge ships no aarch64 build for four of MFA's dependencies:

- **baumwelch** and **ngram** - built from their feedstocks. `fetch-sources.sh` pulls the OpenGrm tarballs because the recipe's own download URL is dead.
- **kalpy** - pinned to 0.9.0. MFA 3.3.9 calls its `TrainingGraphCompiler(use_g2p=...)`, which later releases dropped. 0.9.0 needs a one-line patch to compile on the aarch64 gcc, `kalpy_090/fix-lattice-return.patch`.
- **sox** - installed from Ubuntu apt and removed from MFA's conda dependencies.

## Layout

```
Dockerfile                                          the whole build
fetch-sources.sh                                    downloads and SHA-verifies the OpenGrm tarballs
sources/                                            populated by fetch-sources.sh
  baumwelch-0.3.11.tar.gz
  ngram-1.3.17.tar.gz
patches/                                            feedstock patches
  baumwelch-feedstock__local-source.patch           point the source url at the fetched tarball
  ngram-feedstock__local-source.patch               same for ngram
kalpy_090/
  fix-lattice-return.patch                          C++ backport so kalpy 0.9.0 compiles
```

## Pinned versions

- montreal-forced-aligner 3.3.9
- kalpy 0.9.0
- kaldi 5.5.1172 cpu
- openfst 1.8.4
- baumwelch 0.3.11
- ngram 1.3.17

These match the set shipped by the [official amd64 image](https://hub.docker.com/r/mmcauliffe/montreal-forced-aligner).

## Updating

conda-forge is a moving target: the feedstock default branches advance and the channel resolves the rest of the dependency tree live. Every input here is therefore pinned - the base image by digest, the four feedstocks by commit, and conda-build, conda-forge-pinning, the package versions and source hashes by value. To move to a newer MFA:

- Re-pin `MFA_FEEDSTOCK` to a specific montreal-forced-aligner-feedstock commit and set `MFA_VERSION` to match it. Do not track the branch head. When this was written the feedstock had already advanced from build number 2 to 3 and relaxed its kalpy pin, the kind of silent drift the pin prevents.
- Confirm the recipe edits still fit that commit: one `number:` line to bump, a `sox` run dependency to drop, and a kalpy pin the built version satisfies.
- If the new MFA needs a different kalpy, set `KALPY_VERSION` and `KALPY_SHA256` from the kalpy-kaldi release on PyPI, and check whether `kalpy_090/fix-lattice-return.patch` still applies or is even needed. Later kalpy dropped the `use_g2p` API MFA calls, so the version is not a free choice.
- Refresh the base image digest and the other feedstock commits the same way.

After any bump, run a `--no-cache` build and the align check. Pinned inputs keep rebuilds compatible, but the transitive conda-forge solve is not bit-identical, so only a real build confirms it still works.

## References

- Montreal Forced Aligner - [documentation](https://montreal-forced-aligner.readthedocs.io/) and [source](https://github.com/MontrealCorpusTools/Montreal-Forced-Aligner)
- Official Docker images, amd64 only - [Docker Hub](https://hub.docker.com/r/mmcauliffe/montreal-forced-aligner) and [installation docs](https://montreal-forced-aligner.readthedocs.io/en/latest/installation.html#docker-installation)
- Training an acoustic model - [MFA user guide](https://montreal-forced-aligner.readthedocs.io/en/latest/user_guide/workflows/train_acoustic_model.html)
- MFA 3.3.9 - [release notes](https://github.com/MontrealCorpusTools/Montreal-Forced-Aligner/releases/tag/v3.3.9)
