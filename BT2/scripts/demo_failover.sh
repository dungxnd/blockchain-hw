#!/bin/bash
# ==============================================================================
# Script: demo_failover.sh (Bash for Linux / macOS / Git Bash / WSL)
# Mô tả: Kịch bản tự động kiểm tra cơ chế bầu cử (Leader Election), Chịu lỗi (Failover)
#        và Đạt đồng thuận (Consensus) khi một hoặc nhiều node gặp sự cố.
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}   DEMO CƠ CHẾ ĐỒNG THUẬN VÀ BẦU CỬ LEADER TRÊN MONGODB 3 NODES       ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# BƯỚC 1: Kiểm tra trạng thái ban đầu
echo -e "\n${YELLOW}[BƯỚC 1] Trạng thái cụm ban đầu (Cả 3 node đang hoạt động):${NC}"
docker exec -it mongo1 mongosh --quiet --eval "
  const s = rs.status();
  print('Current Term: ' + s.term);
  s.members.forEach(m => print('-> ' + m.name + ': ' + m.stateStr + ' (Health: ' + m.health + ')'));
"

# BƯỚC 2: Ghi dữ liệu vào Primary hiện tại
echo -e "\n${YELLOW}[BƯỚC 2] Ghi dữ liệu ban đầu vào Primary mongo1:${NC}"
docker exec -it mongo1 mongosh --quiet --eval "
  const res = db.getSiblingDB('blockchain_db').records.insertOne(
    { step: 1, message: 'Ghi vao Primary mongo1 truoc khi failover', time: new Date() },
    { writeConcern: { w: 'majority', wtimeout: 5000 } }
  );
  print('Ghi thanh cong Document ID: ' + res.insertedId);
"

# BƯỚC 3: Đánh sập node Primary (mongo1)
echo -e "\n${RED}[BƯỚC 3] Giả lập sự cố: Dừng container mongo1 (Primary)...${NC}"
docker stop mongo1

echo -e "${YELLOW}Chờ 5 giây để 2 node còn lại phát hiện mất heartbeat và tổ chức bầu cử...${NC}"
sleep 5

# BƯỚC 4: Kiểm tra kết quả bầu cử trên mongo2/mongo3
echo -e "\n${GREEN}[BƯỚC 4] Kiểm tra Leader mới được bầu chọn theo cơ chế đa số (Quorum = 2/3):${NC}"
docker exec -it mongo2 mongosh --quiet --eval "
  const s = rs.status();
  print('New Election Term: ' + s.term);
  s.members.forEach(m => print('-> ' + m.name + ': ' + m.stateStr + ' (Health: ' + m.health + ')'));
"

# BƯỚC 5: Ghi dữ liệu mới vào Primary mới
echo -e "\n${YELLOW}[BƯỚC 5] Ghi dữ liệu tiếp theo vào Primary mới để kiểm tra tính liên tục:${NC}"
docker exec -it mongo2 mongosh --quiet --eval "
  try {
    const res = db.getSiblingDB('blockchain_db').records.insertOne(
      { step: 2, message: 'Ghi vao Leader moi trong khi mongo1 bi down', time: new Date() },
      { writeConcern: { w: 'majority', wtimeout: 5000 } }
    );
    print('Ghi thanh cong vao Leader moi! Document ID: ' + res.insertedId);
  } catch(e) {
    print('Node mongo2 khong phai Primary (co the mongo3 la Primary): ' + e.message);
  }
"

# BƯỚC 6: Khôi phục lại mongo1
echo -e "\n${BLUE}[BƯỚC 6] Khởi động lại container mongo1 (node cũ gặp sự cố đã hồi phục)...${NC}"
docker start mongo1

echo -e "${YELLOW}Chờ 5 giây để mongo1 kết nối lại cụm và đồng bộ Oplog...${NC}"
sleep 5

# BƯỚC 7: Kiểm tra mongo1 gia nhập lại với vai trò SECONDARY và nhận đủ dữ liệu
echo -e "\n${GREEN}[BƯỚC 7] Trạng thái sau khi phục hồi: mongo1 tái gia nhập với vai trò SECONDARY:${NC}"
docker exec -it mongo2 mongosh --quiet --eval "
  const s = rs.status();
  s.members.forEach(m => print('-> ' + m.name + ': ' + m.stateStr + ' (Health: ' + m.health + ')'));
"

echo -e "\n${GREEN}[HOÀN TẤT] Hệ thống đã chứng minh thành công tính sẵn sàng cao và cơ chế đồng thuận phân tán!${NC}"
