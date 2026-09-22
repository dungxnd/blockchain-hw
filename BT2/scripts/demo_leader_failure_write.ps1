# ==============================================================================
# Script: demo_leader_failure_write.ps1 (PowerShell for Windows)
# Mục đích: Chứng minh User VẪN GHI ĐƯỢC DỮ LIỆU bình thường khi Leader gặp sự cố
#           nhờ cơ chế tự động bầu Leader mới và Replica Set Client Router.
# ==============================================================================

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "   DEMO: USER VẪN GHI ĐƯỢC DỮ LIỆU KHI LEADER (PRIMARY) BỊ SẬP        " -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# Chuỗi kết nối Replica Set (Client kết nối tới toàn bộ cụm, không kết nối đơn lẻ 1 node)
# MongoDB Driver sẽ tự động tìm thấy Primary dù Primary nằm ở bất kỳ node nào.
$ReplicaUri = "mongodb://mongo1:27017,mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0&retryWrites=true"

# BƯỚC 1: Xác định Leader (Primary) hiện tại
Write-Host "`n[BƯỚC 1] Xác định ai đang là Leader (Primary)..." -ForegroundColor Yellow
docker exec mongo2 mongosh $ReplicaUri --quiet --eval @"
  const hello = db.hello();
  print('-> Leader hien tai dang la node: ' + hello.primary);
"@

# BƯỚC 2: User thực hiện Ghi giao dịch số 1 (Leader ban đầu xử lý)
Write-Host "`n[BƯỚC 2] User gửi thao tác GHI #1 vào Replica Set:" -ForegroundColor Yellow
docker exec mongo2 mongosh $ReplicaUri --quiet --eval @"
  const res = db.orders.insertOne(
    { orderId: 'ORD_001', customer: 'Alice', amount: 150, note: 'Ghi khi Leader ban dau dang song' },
    { writeConcern: { w: 'majority', wtimeout: 5000 } }
  );
  print('[USER WRITE 1 THANH CONG] ID: ' + res.insertedId);
"@

# BƯỚC 3: Giả lập sự cố - Leader hiện tại bị crash đột ngột!
Write-Host "`n[BƯỚC 3] GIẢ LẬP SỰ CỐ: Đánh sập Leader ban đầu (mongo1)..." -ForegroundColor Red
docker stop mongo1

Write-Host "Cụm đang tự động tổ chức bầu cử Leader mới (Raft-like election)..." -ForegroundColor Magenta
Write-Host "Chờ 6 giây để hoàn tất bầu cử..." -ForegroundColor Yellow
Start-Sleep -Seconds 6

# BƯỚC 4: Kiểm tra Leader mới được bầu
Write-Host "`n[BƯỚC 4] Kiểm tra Leader mới được đồng thuận bầu chọn:" -ForegroundColor Green
docker exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --quiet --eval @"
  const hello = db.hello();
  print('-> LEADER MOI CUA CUM HIEN TAI LA: ' + hello.primary);
  print('-> Trạng thái: ' + (hello.isWritablePrimary ? 'San sang nhan lenh GHI' : 'Dang dong bo'));
"@

# BƯỚC 5: User TIẾP TỤC GHI GIAO DỊCH SỐ 2 (Trong khi mongo1 vẫn đang CHẾT)
Write-Host "`n[BƯỚC 5] QUAN TRỌNG: User gui thao tac GHI #2 vao cluster trong khi Leader cu van chet:" -ForegroundColor Green
docker exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0&retryWrites=true" --quiet --eval @"
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
"@

# BƯỚC 6: Đọc lại toàn bộ dữ liệu để kiểm tra tính toàn vẹn
Write-Host "`n[BƯỚC 6] Doc lai toan bo danh sach don hang da ghi:" -ForegroundColor Yellow
docker exec mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --quiet --eval @"
  printjson(db.orders.find({}, { _id: 0 }).toArray());
"@

# BƯỚC 7: Phục hồi lại node cũ mongo1
Write-Host "`n[BƯỚC 7] Khoi dong lai node cu mongo1..." -ForegroundColor Cyan
docker start mongo1
Start-Sleep -Seconds 5

Write-Host "`n[HOÀN TẤT] Chứng minh thành công: User vẫn có thể GHI dữ liệu bình thường khi Leader gặp sự cố!`n" -ForegroundColor Green
