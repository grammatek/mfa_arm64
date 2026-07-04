# Montreal Forced Aligner for linux-aarch64, for example the NVIDIA DGX Spark.
#
# MFA itself is a noarch conda package, but four of its dependencies have no
# linux-aarch64 build on conda-forge, blocking MFA on ARM Linux:
#   - baumwelch and ngram from OpenGrm are built here from their feedstocks.
#   - kalpy, the Kaldi python bindings, is built here and must be version 0.9.0.
#     MFA 3.3.9 calls TrainingGraphCompiler with the use_g2p argument that later
#     kalpy releases removed. Version 0.9.0 does not compile on the aarch64 gcc,
#     so kalpy_090/fix-lattice-return.patch backports the one-line upstream fix.
#   - sox is not on conda-forge for aarch64 at all. It is therefore installed from
#     Ubuntu apt and dropped from MFA's conda run dependencies.
#
# Build natively on arm64:   docker build -t mfa-arm64:latest .
# Cross-build from amd64:     docker buildx build --platform linux/arm64 -t mfa-arm64:latest --load .
FROM condaforge/miniforge3@sha256:70ce395025aeec0d011eb64b6d6dc870fcc1a774a163965bc6dd8e8f6bf5da0d

SHELL ["/bin/bash", "-lc"]

# System packages. sox has no conda-forge aarch64 build, so MFA uses the apt binary.
RUN apt-get update && apt-get install -y --no-install-recommends sox && rm -rf /var/lib/apt/lists/*

# conda-forge-pinning supplies the aarch64 compiler, stdlib and platform variant
# pins that the feedstock recipes need when built outside conda-forge CI.
RUN mamba install -y -n base conda-build=26.5.0 git "conda-forge-pinning=2026.07.04.19.07.56" && mamba clean -afy
ENV CBC=/opt/conda/conda_build_config.yaml

# Pinned versions. kalpy 0.9.0 matches MFA's API; see the kalpy build step below.
ARG MFA_VERSION=3.3.9
ARG KALPY_VERSION=0.9.0
ARG KALPY_SHA256=54982b845bb4d13bb909c0c40c5300d78fe0207a840be11543ccf21fd26e8673

# Feedstock commits, pinned so a rebuild uses the same recipes.
ARG BAUMWELCH_FEEDSTOCK=d88f613007d8aa64c21f5becbf2108745dc21f0e
ARG NGRAM_FEEDSTOCK=8bac0e7b4640716b11a7e6665fb46872d28c861e
ARG KALPY_FEEDSTOCK=ccc4729d0f61910728ec7c04778e06a3c11aea0d
ARG MFA_FEEDSTOCK=821324d22106ed5204a381e256c83dd872ba05d6

WORKDIR /build
RUN git clone https://github.com/conda-forge/baumwelch-feedstock.git && git -C baumwelch-feedstock checkout -q "$BAUMWELCH_FEEDSTOCK" \
 && git clone https://github.com/conda-forge/ngram-feedstock.git && git -C ngram-feedstock checkout -q "$NGRAM_FEEDSTOCK" \
 && git clone https://github.com/conda-forge/kalpy-feedstock.git && git -C kalpy-feedstock checkout -q "$KALPY_FEEDSTOCK" \
 && git clone https://github.com/conda-forge/montreal-forced-aligner-feedstock.git && git -C montreal-forced-aligner-feedstock checkout -q "$MFA_FEEDSTOCK"

# The OpenGrm source tarballs, fetched fetch-sources.sh
COPY sources/ /build/sources/

# Local patches: source-url fixes and aarch64 build tweaks. Applied if present.
COPY patches/ /build/patches/
RUN shopt -s nullglob; for p in /build/patches/*.patch; do \
      d=$(basename "$p" .patch); d="${d%%__*}"; \
      echo ">> patch $p -> $d"; git -C "/build/$d" apply -v "$p"; \
    done

# Compile with half the build machine's cores; override with --build-arg JOBS=N.
ARG JOBS
RUN J="${JOBS:-$(( ($(nproc) + 1) / 2 ))}" \
 && echo "export MAKEFLAGS=-j${J} CMAKE_BUILD_PARALLEL_LEVEL=${J}" > /etc/profile.d/parallel.sh

# Build the two missing OpenGrm feedstocks for aarch64 using the conda-forge pinning config,
# so the compiler and stdlib variants resolve.
RUN conda build -m "$CBC" --no-anaconda-upload --no-test -c conda-forge baumwelch-feedstock/recipe
RUN conda build -m "$CBC" --no-anaconda-upload --no-test -c conda-forge ngram-feedstock/recipe

# Pin the kalpy feedstock version to the version MFA 3.3.9 requires.
# MFA calls the kalpy TrainingGraphCompiler use_g2p API that later releases dropped.
# Version 0.9.0 does not compile on the aarch64 gcc because of an inconsistent lambda
# return type in gmm_latgen_faster
COPY kalpy_090/ /build/kalpy_090/
RUN cd kalpy-feedstock \
 && sed -i "s/^{% set version = .*/{% set version = \"${KALPY_VERSION}\" %}/" recipe/meta.yaml \
 && sed -i "s|^  sha256: .*|  sha256: ${KALPY_SHA256}|" recipe/meta.yaml \
 && sed -i '/^  sha256:/a\  patches:\n    - fix-lattice-return.patch' recipe/meta.yaml \
 && cp /build/kalpy_090/fix-lattice-return.patch recipe/ \
 && echo "=== kalpy source stanza ===" && sed -n '9,16p' recipe/meta.yaml

# kalpy, API-matched to MFA
RUN conda build -m "$CBC" --no-anaconda-upload --no-test -c conda-forge kalpy-feedstock/recipe

# Prepare MFA's recipe: bump the build number so our local package wins over the
# conda-forge one, and drop the sox dependency aarch64 lacks. The pinned feedstock
# already relaxes the kalpy pin to >=0.9, which our 0.9.0 satisfies.
RUN cd montreal-forced-aligner-feedstock/recipe \
 && sed -i -E 's/^  number: .*/  number: 100/' meta.yaml \
 && sed -i -E '/^[[:space:]]*-[[:space:]]*sox[[:space:]]*$/d' meta.yaml

# MFA itself
RUN conda build -m "$CBC" --no-anaconda-upload --no-test -c conda-forge montreal-forced-aligner-feedstock/recipe

# Index the local build output into a proper channel with repodata so libmamba can
# read it over file://. conda-build's auto-index leaves no readable zst.
RUN conda index /opt/conda/conda-bld

# Resolve MFA against the freshly built kalpy, baumwelch and ngram plus conda-forge.
# The explicit build 100 selects our local MFA over the conda-forge one, which is
# not built for aarch64.
RUN mamba create -y -n mfa \
    -c file:///opt/conda/conda-bld -c conda-forge \
    "montreal-forced-aligner=${MFA_VERSION}=*_100" \
 && mamba clean -afy
ENV PATH=/opt/conda/envs/mfa/bin:$PATH
ENTRYPOINT ["mfa"]
