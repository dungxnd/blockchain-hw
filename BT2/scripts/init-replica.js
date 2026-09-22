// ==============================================================================
// Script: init-replica.js
// Mục đích: Khởi tạo Replica Set 'rs0' gồm 3 nodes (mongo1, mongo2, mongo3)
// Chạy tự động bởi service mongo-init trong docker-compose.yml
// ==============================================================================

print("----------------------------------------------------------------------");
print("[INIT] Bắt đầu kiểm tra và cấu hình Replica Set 'rs0'...");
print("----------------------------------------------------------------------");

let isInitiated = false;
try {
  const status = rs.status();
  if (status.ok === 1) {
    isInitiated = true;
    print("[INIT] Replica Set 'rs0' đã được khởi tạo trước đó.");
  }
} catch (e) {
  print("[INIT] Replica Set chưa khởi tạo. Đang tiến hành rs.initiate()...");
}

if (!isInitiated) {
  const replicaConfig = {
    _id: "rs0",
    members: [
      { _id: 0, host: "mongo1:27017", priority: 2 }, // Ưu tiên node mongo1 làm PRIMARY ban đầu
      { _id: 1, host: "mongo2:27017", priority: 1 },
      { _id: 2, host: "mongo3:27017", priority: 1 }
    ]
  };

  const initResult = rs.initiate(replicaConfig);
  print("[INIT] Kết quả gọi rs.initiate():", JSON.stringify(initResult));

  if (initResult.ok !== 1) {
    print("[ERROR] Không thể khởi tạo Replica Set:", initResult.errmsg);
    quit(1);
  }
}

// Chờ bầu chọn (Leader Election) hoàn tất và xác định node PRIMARY
print("[INIT] Đang chờ hoàn tất bầu cử (Leader Election) theo thuật toán đồng thuận...");

let electedPrimary = null;
for (let attempt = 1; attempt <= 30; attempt++) {
  try {
    const hello = db.hello();
    if (hello.isWritablePrimary) {
      electedPrimary = hello.me;
      break;
    } else if (hello.primary) {
      electedPrimary = hello.primary;
      break;
    }
  } catch (err) {
    // Có thể đang trong quá trình chuyển trạng thái
  }
  sleep(1000);
}

if (electedPrimary) {
  print("======================================================================");
  print("[SUCCESS] Replica Set đã thiết lập thành công!");
  print(`[SUCCESS] Node PRIMARY được đồng thuận bầu chọn: ${electedPrimary}`);
  print("======================================================================");
} else {
  print("[WARNING] Đã hết thời gian chờ nhưng chưa xác định được PRIMARY.");
}
