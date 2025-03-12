FROM julia:1.11.4-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y build-essential

COPY Project.toml .
COPY Manifest.toml .
COPY build.jl .
ADD src src/.
ADD test test/.

RUN julia build.jl -t auto -O3 --startup-file=no --heap-size-hint=6G

FROM julia:1.11.3-bookworm

WORKDIR /app

COPY --from=builder /app/target/ .

RUN echo "deb http://ftp.debian.org/debian sid main" >> /etc/apt/sources.list
RUN apt-get update && apt-get install -y libc6

# Cleanup julia stuff we don't need
RUN rm -rf /usr/local/julia/lib/julia
RUN rm -rf /usr/local/julia/share/julia/compiled/v1.11/Pkg
RUN rm -rf /usr/local/julia/share/julia/compiled/v1.11/REPL
RUN rm -rf /usr/local/julia/share/doc

ENV PATH=/app/bin:${PATH}

CMD ["/bin/bash"]
