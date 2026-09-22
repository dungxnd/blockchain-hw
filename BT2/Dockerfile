# ==============================================================================
# Dockerfile: Tối ưu siêu nhẹ (Lightweight) dùng debian:bookworm-slim thay vì Ubuntu
#
# LÝ DO KHÔNG DÙNG ALPINE:
#   - MongoDB Server phụ thuộc chặt chẽ vào thư viện GNU C (glibc) và các cơ chế
#     bộ nhớ/fsync của WiredTiger. Alpine sử dụng musl libc dẫn đến crash hoặc lỗi ngầm.
#   - MongoDB chính thức KHÔNG phát hành gói apk cho Alpine (đã bị gỡ khỏi Alpine repos).
#   - Giải pháp chuẩn công nghiệp nhẹ nhất: "debian:bookworm-slim" (Base image chỉ ~30MB,
#     nhỏ hơn nhiều so với Ubuntu và tương thích 100% chính thức với MongoDB).
# ==============================================================================
FROM debian:bookworm-slim

LABEL maintainer="VNU-UET Blockchain Course"
LABEL description="Lightweight Debian-slim MongoDB 7.0 Community Server image with mongosh"

ENV DEBIAN_FRONTEND=noninteractive

# 1. Cài đặt các gói tối thiểu và làm sạch cache ngay lập tức để giữ dung lượng nhỏ
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    procps \
    && rm -rf /var/lib/apt/lists/*

# 2. Thêm MongoDB GPG Key và Repository chính thức cho Debian Bookworm (MongoDB 7.0)
RUN curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
    gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor \
    && echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | \
    tee /etc/apt/sources.list.d/mongodb-org-7.0.list

# 3. Cài đặt MongoDB server và mongosh, lược bỏ tài liệu & gói khuyến nghị
RUN apt-get update && apt-get install -y --no-install-recommends \
    mongodb-org \
    mongodb-mongosh \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /usr/share/doc/* /usr/share/man/*

# 4. Thiết lập thư mục dữ liệu và quyền hạn
RUN mkdir -p /data/db /data/configdb \
    && chown -R mongodb:mongodb /data/db /data/configdb

# 5. Đóng gói trực tiếp thư mục scripts vào image (tránh lỗi mount ổ đĩa /mnt/d trên Podman Windows)
COPY scripts/ /scripts/
RUN chown -R mongodb:mongodb /scripts && chmod -R +rx /scripts

# 6. Đảm bảo phân quyền truy cập cho thư mục dữ liệu
RUN chmod -R 777 /data/db /data/configdb

EXPOSE 27017

CMD ["mongod", "--bind_ip_all"]
