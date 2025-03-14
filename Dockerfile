FROM julia:1.11.4-bookworm AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y build-essential

COPY Project.toml .
COPY build.jl .
ADD src src/.
ADD test test/.

RUN julia build.jl -t auto -O3 --startup-file=no --heap-size-hint=6G

FROM debian:bookworm

WORKDIR /app

COPY --from=builder /app/target/ .

RUN echo "deb http://ftp.debian.org/debian sid main" >> /etc/apt/sources.list
RUN apt-get update && apt-get install -y libc6

ENV PATH=/app/bin:${PATH}

CMD ["/bin/bash", "-c"]
ENTRYPOINT ["stonks --help"]
