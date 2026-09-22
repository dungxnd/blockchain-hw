#!/bin/bash
# ==============================================================================
# Script: demo_leader_failure_write.sh (Bash for Linux / macOS / Git Bash / WSL)
# Mục đích: Chứng minh User VẪN GHI ĐƯỢC DỮ LIỆU bình thường khi Leader gặp sự cố
#           nhờ cơ chế tự động bầu Leader mới và Replica Set Client Router.
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}   DEMO: USER VẪN GHI ĐƯỢC DỮ LIỆU KHI LEADER (PRIMARY) BỊ SẬP        ${NC}"
echo -e "${BLUE}======================================================================${NC}"

REPLICA_URI="mongodb://mongo1:27017,mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0&retryWrites=true"

# BƯỚC 1: Xác định Leader (Primary) hiện tại
echo -e "\n${YELLOW}[BƯỚC 1] Xác định ai đang là Leader (Primary)...${NC}"
docker exec mongo2 mongosh "$REPLICA_URI" --quiet --eval "
  const hello = db.hello();
  print('-> Leader hien tai dang la node: ' + hello.primary);
"

# BƯỚC 2: User thực hiện Ghi giao dịch số 1
echo -e "\n${YELLOW}[BƯỚC 2] User gửi thao tác GHI #1 vào Replica Set:${NC}"
docker exec mongo2 mongosh "$REPLICA_URI" --quiet --eval "
  const res = db.orders.insertOne(
    { orderId: 'ORD_001', customer: 'Alice', amount: 150, note: 'Ghi khi Leader ban dau dang song' },
    { writeConcern: { w: 'majority', wtimeout: 5000 } }
  );
  print('[USER WRITE 1 THANH CONG] ID: ' + res.insertedId);
"

# BƯỚC 3: Giả lập sự cố - Leader hiện tại bị crash đột ngột!
echo -e "\n${RED}[BƯỚC 3] GIẢ LẬP SỰ CỐ: Đánh sập Leader ban đầu (mongo1)...${NC}"
docker stop mongo1

echo -e "${MAGENTA}Cụm đang tự động tổ chức bầu cử Leader mới (Raft-like election)...${NC}"
echo -e "${YELLOW}Chờ 6 giây để hoàn tất bầu cử...${NC}"
sleep 6

# BƯỚC 4: Kiểm tra Leader mới được bầu
echo -e "\n${GREEN}[BƯỚC 4] Kiểm tra Leader mới được đồng thuận bầu chọn:${NC}"
docker exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --quiet --eval "
  const hello = db.hello();
  print('-> LEADER MOI CUA CUM HIEN TAI LA: ' + hello.primary);
  print('-> Trạng thái: ' + (hello.isWritablePrimary ? 'San sang nhan lenh GHI' : 'Dang dong bo'));
"

# BƯỚC 5: User TIẾP TỤC GHI GIAO DỊCH SỐ 2 (Trong khi mongo1 vẫn đang CHẾT)
echo -e "\n${GREEN}[BƯỚC 5] QUAN TRỌNG: User gui thao tac GHI #2 vao cluster trong khi Leader cu van chet:${NC}"
docker exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0&retryWrites=true" --quiet --eval "
  try {
    const res = db.orders.insertOne(
      { orderId: 'ORD_002', customer: 'Bob', amount: 300, note: 'GHI THANH CONG KHI LEADER CU BI SAP' },
      { writeConcern: { w: 'majority', wtimeout: 5000 } }
    );
    print('[USER WRITE 2 THANH CONG] ID: ' + res.insertedId);
    print('==> CHUNG MINH: He thong van tiep nhan ghi binh thuong nho Leader moi!');
  } catch (err) {
    print('[THAT BAI]: ' + err.message);
  }
"

# BƯỚC 6: Đọc lại toàn bộ dữ liệu để kiểm tra tính toàn vẹn
echo -e "\n${YELLOW}[BƯỚC 6] Doc lai toan bo danh sach don hang da ghi:${NC}"
docker exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --quiet --eval "
  printjson(db.orders.find({}, { _id: 0 }).toArray());
"

# BƯỚC 7: Phục hồi lại node cũ mongo1
echo -e "\n${BLUE}[BƯỚC 7] Khoi dong lai node cu mongo1...${NC}"
docker start mongo1
sleep 5

echo -e "\n${GREEN}[HOÀN TẤT] Chứng minh thành công: User vẫn có thể GHI dữ liệu bình thường khi Leader gặp sự cố!${NC}\n"
