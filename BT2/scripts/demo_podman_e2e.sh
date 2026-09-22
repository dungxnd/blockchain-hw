#!/bin/bash
# ==============================================================================
# Script: demo_podman_e2e.sh (Podman for Linux / macOS / WSL)
# Kịch bản E2E: Kiểm tra Leader, Giết Leader, và Chứng minh User vẫn GHI thành công
# ==============================================================================

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}======================================================================${NC}"
echo -e "${BLUE}     E2E PODMAN DEMO: REPLICATION CONSENSUS & WRITE RESILIENCE         ${NC}"
echo -e "${BLUE}======================================================================${NC}"

# 1. KIỂM TRA LEADER HIỆN TẠI
echo -e "\n${YELLOW}[BƯỚC 1] Kiểm tra Leader (Primary) ban đầu:${NC}"
podman exec mongo2 mongosh "mongodb://mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet --eval "
  const s = rs.status();
  print('-> Election Term: ' + s.term);
  print('-> LEADER HIEN TAI: ' + db.hello().primary);
  s.members.forEach(m => print('   * ' + m.name + ' => ' + m.stateStr + ' (Health: ' + m.health + ')'));
"

# 2. GHI DỮ LIỆU KHI CỤM ĐANG HOẠT ĐỘNG BÌNH THƯỜNG
echo -e "\n${YELLOW}[BƯỚC 2] User gửi thao tác GHI #1 vào cụm:${NC}"
podman exec mongo2 mongosh "mongodb://mongo1:27017,mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --quiet --eval "
  const res = db.orders.insertOne(
    { orderId: 'TX_001', item: 'GPU RTX 4090', note: 'Ghi khi Leader mongo1 con hoat dong' },
    { writeConcern: { w: 'majority', wtimeout: 5000 } }
  );
  print('[GHI THANH CONG TX_001] ID: ' + res.insertedId);
"

# 3. GIẢ LẬP SỰ CỐ: ĐÁNH SẬP LEADER (mongo1 DIE/ERR)
echo -e "\n${RED}[BƯỚC 3] Giả lập sự cố: podman stop mongo1 (Leader đã chết)...${NC}"
podman stop mongo1

echo -e "${YELLOW}Chờ 6 giây để cụm tổ chức bầu Leader mới theo luật đa số (2/3 nodes)...${NC}"
sleep 6

# 4. KIỂM TRA LEADER MỚI ĐƯỢC BẦU
echo -e "\n${GREEN}[BƯỚC 4] Kiểm tra Leader mới được đồng thuận bầu chọn:${NC}"
podman exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet --eval "
  const s = rs.status();
  print('-> Election Term moi: ' + s.term);
  print('-> LEADER MOI CUA CUM: ' + db.hello().primary);
  s.members.forEach(m => print('   * ' + m.name + ' => ' + m.stateStr + ' (Health: ' + m.health + ')'));
"

# 5. USER TIẾP TỤC GHI THÀNH CÔNG KHI LEADER CŨ ĐÃ CHẾT
echo -e "\n${GREEN}[BƯỚC 5] USER GHI GIAO DỊCH #2 KHI LEADER CŨ (mongo1) ĐÃ CHẾT:${NC}"
podman exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0&retryWrites=true" --quiet --eval "
  try {
    const res = db.orders.insertOne(
      { orderId: 'TX_002', item: 'ASIC Miner', note: 'GHI THANH CONG KHI LEADER CU DED' },
      { writeConcern: { w: 'majority', wtimeout: 5000 } }
    );
    print('[GHI THANH CONG TX_002] Acknowledged: ' + res.acknowledged + ' | ID: ' + res.insertedId);
    print('==> CHUNG MINH: User van ghi du lieu binh thuong nho Leader moi!');
  } catch(e) {
    print('[LOI]: ' + e.message);
  }
"

# 6. KIỂM TRA TOÀN BỘ DỮ LIỆU
echo -e "\n${YELLOW}[BƯỚC 6] Đọc lại toàn bộ dữ liệu để kiểm tra tính toàn vẹn:${NC}"
podman exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --quiet --eval "
  printjson(db.orders.find({}, { _id: 0 }).toArray());
"

# 7. HỒI SINH LEADER CŨ
echo -e "\n${BLUE}[BƯỚC 7] Hồi sinh lại node cũ (podman start mongo1)...${NC}"
podman start mongo1
sleep 5
podman exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet --eval "
  print('Trang thai sau hoi phuc:');
  rs.status().members.forEach(m => print('   * ' + m.name + ' => ' + m.stateStr + ' (Health: ' + m.health + ')'));
"

echo -e "\n${GREEN}[HOÀN THÀNH DEMO PODMAN E2E!]${NC}\n"
