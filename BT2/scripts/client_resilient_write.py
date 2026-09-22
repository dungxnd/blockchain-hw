#!/usr/bin/env python3
# ==============================================================================
# Script: client_resilient_write.py
# Mục đích: Mô phỏng ứng dụng Client liên tục ghi dữ liệu vào Replica Set.
#           Minh chứng: Khi Leader gặp sự cố, Client tự động chuyển hướng và tiếp tục
#           ghi thành công vào Leader mới mà không làm gián đoạn nghiệp vụ.
# Yêu cầu: pip install pymongo (nếu chạy trực tiếp trên máy host)
# ==============================================================================

import time
import sys
from pymongo import MongoClient
from pymongo.errors import AutoReconnect, ServerSelectionTimeoutError

# Chuỗi kết nối Replica Set: Liệt kê các node để driver tự động khám phá Leader
CONNECTION_URI = (
    "mongodb://localhost:27017,localhost:27018,localhost:27019/"
    "?replicaSet=rs0&retryWrites=true&serverSelectionTimeoutMS=15000"
)

def main():
    print("=" * 70)
    print("  DEMO CLIENT CHỊU LỖI: LIÊN TỤC GHI DỮ LIỆU KHI LEADER CRASH")
    print("=" * 70)
    print(f"[*] Đang kết nối tới Replica Set: {CONNECTION_URI}\n")

    try:
        client = MongoClient(CONNECTION_URI)
        db = client["blockchain_db"]
        collection = db["resilient_txs"]

        # Kiểm tra node Leader hiện tại
        primary = client.primary
        print(f"[+] Kết nối thành công! Leader (Primary) hiện tại: {primary}")
        print("[+] Bắt đầu vòng lặp ghi dữ liệu mỗi 2 giây...")
        print("[!] BẠN CÓ THỂ THỬ CHẠY LỆNH 'docker stop mongo1' TRÊN TERMINAL KHÁC ĐỂ XEM KẾT QUẢ.\n")

        tx_count = 0
        while tx_count < 15:
            tx_count += 1
            record = {
                "tx_id": f"TX_{tx_count:04d}",
                "timestamp": time.time(),
                "time_str": time.strftime("%H:%M:%S"),
                "status": "CONFIRMED"
            }

            try:
                # Ghi với cam kết đồng thuận đa số (w: "majority")
                res = collection.with_options(
                    write_concern=client.write_concern.copy(w="majority", wtimeout=10000)
                ).insert_one(record)

                current_primary = client.primary
                print(f"[{time.strftime('%H:%M:%S')}] [GHI THÀNH CÔNG] Tx #{tx_count} "
                      f"(ID: {res.insertedId}) -> Ghi tới Leader: {current_primary}")

            except AutoReconnect as e:
                # Hiện tượng xảy ra trong vài giây khi Leader cũ sập và Leader mới đang được bầu
                print(f"[{time.strftime('%H:%M:%S')}] [CẢNH BÁO - ĐANG BẦU CỬ] Mất kết nối tới Leader cũ, "
                      f"Driver đang chờ Leader mới được bầu... ({e})")
                time.sleep(2)
                continue

            except ServerSelectionTimeoutError as e:
                print(f"[{time.strftime('%H:%M:%S')}] [LỖI TIMEOUT] Không tìm thấy Leader: {e}")
                time.sleep(2)
                continue

            time.sleep(2)

        print("\n" + "=" * 70)
        print(f"[HOÀN THÀNH] Tổng số bản ghi đã ghi thành công: {collection.count_documents({})}")
        print(f"[+] Leader phục vụ cuối cùng: {client.primary}")
        print("=" * 70)

    except Exception as err:
        print(f"[LỖI KHỞI ĐỘNG]: {err}")
        sys.exit(1)

if __name__ == "__main__":
    main()
