# ==============================================================================
# Script: demo_failover.ps1 (PowerShell for Windows)
# Mô tả: Kịch bản tự động kiểm tra cơ chế bầu cử (Leader Election), Chịu lỗi (Failover)
#        và Đạt đồng thuận (Consensus) trên môi trường Windows PowerShell.
# ==============================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "   DEMO CƠ CHẾ ĐỒNG THUẬN VÀ BẦU CỬ LEADER TRÊN MONGODB 3 NODES       " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# BƯỚC 1: Kiểm tra trạng thái ban đầu
Write-Host "`n[BƯỚC 1] Trạng thái cụm ban đầu (Cả 3 node đang hoạt động):" -ForegroundColor Yellow
docker exec mongo1 mongosh --quiet --eval @"
  const s = rs.status();
  print('Current Term: ' + s.term);
  s.members.forEach(m => print('-> ' + m.name + ': ' + m.stateStr + ' (Health: ' + m.health + ')'));
"@

# BƯỚC 2: Ghi dữ liệu vào Primary hiện tại
Write-Host "`n[BƯỚC 2] Ghi dữ liệu ban đầu vào Primary mongo1:" -ForegroundColor Yellow
docker exec mongo1 mongosh --quiet --eval @"
  const res = db.getSiblingDB('blockchain_db').records.insertOne(
    { step: 1, message: 'Ghi vao Primary mongo1 truoc khi failover', time: new Date() },
    { writeConcern: { w: 'majority', wtimeout: 5000 } }
  );
  print('Ghi thanh cong Document ID: ' + res.insertedId);
"@

# BƯỚC 3: Đánh sập node Primary (mongo1)
Write-Host "`n[BƯỚC 3] Giả lập sự cố: Dừng container mongo1 (Primary)..." -ForegroundColor Red
docker stop mongo1

Write-Host "Chờ 6 giây để 2 node còn lại phát hiện mất heartbeat và tổ chức bầu cử..." -ForegroundColor Yellow
Start-Sleep -Seconds 6

# BƯỚC 4: Kiểm tra kết quả bầu cử trên mongo2/mongo3
Write-Host "`n[BƯỚC 4] Kiểm tra Leader mới được bầu chọn theo cơ chế đa số (Quorum = 2/3):" -ForegroundColor Green
docker exec mongo2 mongosh --quiet --eval @"
  const s = rs.status();
  print('New Election Term: ' + s.term);
  s.members.forEach(m => print('-> ' + m.name + ': ' + m.stateStr + ' (Health: ' + m.health + ')'));
"@

# BƯỚC 5: Ghi dữ liệu mới vào cụm
Write-Host "`n[BƯỚC 5] Ghi dữ liệu tiếp theo vào cluster (qua mongo2 hoặc mongo3):" -ForegroundColor Yellow
docker exec mongo2 mongosh --quiet --eval @"
  try {
    const res = db.getSiblingDB('blockchain_db').records.insertOne(
      { step: 2, message: 'Ghi vao Leader moi trong khi mongo1 bi down', time: new Date() },
      { writeConcern: { w: 'majority', wtimeout: 5000 } }
    );
    print('Ghi thanh cong qua mongo2! Document ID: ' + res.insertedId);
  } catch(e) {
    print('mongo2 khong phai Primary: ' + e.message + ' (thu ghi qua mongo3)');
  }
"@

# BƯỚC 6: Khôi phục lại mongo1
Write-Host "`n[BƯỚC 6] Khởi động lại container mongo1 (node cũ đã hồi phục)..." -ForegroundColor Cyan
docker start mongo1

Write-Host "Chờ 6 giây để mongo1 kết nối lại cụm và đồng bộ Oplog..." -ForegroundColor Yellow
Start-Sleep -Seconds 6

# BƯỚC 7: Kiểm tra mongo1 gia nhập lại với vai trò SECONDARY
Write-Host "`n[BƯỚC 7] Trạng thái sau phục hồi: mongo1 tái gia nhập với vai trò SECONDARY:" -ForegroundColor Green
docker exec mongo2 mongosh --quiet --eval @"
  const s = rs.status();
  s.members.forEach(m => print('-> ' + m.name + ': ' + m.stateStr + ' (Health: ' + m.health + ')'));
"@

Write-Host "`n[HOÀN TẤT] Hệ thống đã chứng minh thành công tính sẵn sàng cao và cơ chế đồng thuận phân tán!`n" -ForegroundColor Green
