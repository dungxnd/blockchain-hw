# ==============================================================================
# Script: demo_podman_e2e.ps1 (Podman for Windows PowerShell)
# Kịch bản E2E: Kiểm tra Leader, Giết Leader, và Chứng minh User vẫn GHI thành công
# ==============================================================================

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "     E2E PODMAN DEMO: REPLICATION CONSENSUS & WRITE RESILIENCE         " -ForegroundColor Cyan
Write-Host "======================================================================`n" -ForegroundColor Cyan

# 1. KIỂM TRA LEADER HIỆN TẠI
Write-Host "[BƯỚC 1] Kiểm tra Leader (Primary) ban đầu:" -ForegroundColor Yellow
podman exec mongo2 mongosh "mongodb://mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet --eval @"
  const s = rs.status();
  print('-> Election Term: ' + s.term);
  print('-> LEADER HIEN TAI: ' + db.hello().primary);
  s.members.forEach(m => print('   * ' + m.name + ' => ' + m.stateStr + ' (Health: ' + m.health + ')'));
"@

# 2. GHI DỮ LIỆU KHI CỤM ĐANG HOẠT ĐỘNG BÌNH THƯỜNG
Write-Host "`n[BƯỚC 2] User gửi thao tác GHI #1 vào cụm:" -ForegroundColor Yellow
podman exec mongo2 mongosh "mongodb://mongo1:27017,mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --quiet --eval @"
  const res = db.orders.insertOne(
    { orderId: 'TX_001', item: 'GPU RTX 4090', note: 'Ghi khi Leader mongo1 con hoat dong' },
    { writeConcern: { w: 'majority', wtimeout: 5000 } }
  );
  print('[GHI THANH CONG TX_001] ID: ' + res.insertedId);
"@

# 3. GIẢ LẬP SỰ CỐ: ĐÁNH SẬP LEADER (mongo1 DIE/ERR)
Write-Host "`n[BƯỚC 3] Giả lập sự cố: podman stop mongo1 (Leader đã chết)..." -ForegroundColor Red
podman stop mongo1

Write-Host "Chờ 6 giây để cụm tổ chức bầu Leader mới theo luật đa số (2/3 nodes)..." -ForegroundColor Magenta
Start-Sleep -Seconds 6

# 4. KIỂM TRA LEADER MỚI ĐƯỢC BẦU
Write-Host "`n[BƯỚC 4] Kiểm tra Leader mới được đồng thuận bầu chọn:" -ForegroundColor Green
podman exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet --eval @"
  const s = rs.status();
  print('-> Election Term moi: ' + s.term);
  print('-> LEADER MOI CUA CUM: ' + db.hello().primary);
  s.members.forEach(m => print('   * ' + m.name + ' => ' + m.stateStr + ' (Health: ' + m.health + ')'));
"@

# 5. USER TIẾP TỤC GHI THÀNH CÔNG KHI LEADER CŨ ĐÃ CHẾT
Write-Host "`n[BƯỚC 5] USER GHI GIAO DỊCH #2 KHI LEADER CŨ (mongo1) ĐÃ CHẾT:" -ForegroundColor Green
podman exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0&retryWrites=true" --quiet --eval @"
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
"@

# 6. KIỂM TRA TOÀN BỘ DỮ LIỆU
Write-Host "`n[BƯỚC 6] Đọc lại toàn bộ dữ liệu để kiểm tra tính toàn vẹn:" -ForegroundColor Yellow
podman exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --quiet --eval @"
  printjson(db.orders.find({}, { _id: 0 }).toArray());
"@

# 7. HỒI SINH LEADER CŨ
Write-Host "`n[BƯỚC 7] Hồi sinh lại node cũ (podman start mongo1)..." -ForegroundColor Cyan
podman start mongo1
Start-Sleep -Seconds 5
podman exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/?replicaSet=rs0" --quiet --eval @"
  print('Trang thai sau hoi phuc:');
  rs.status().members.forEach(m => print('   * ' + m.name + ' => ' + m.stateStr + ' (Health: ' + m.health + ')'));
"@

Write-Host "`n[HOÀN THÀNH DEMO PODMAN E2E!]`n" -ForegroundColor Green
