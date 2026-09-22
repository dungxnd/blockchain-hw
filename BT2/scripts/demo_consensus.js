// ==============================================================================
// Script: demo_consensus.js
// Mục đích: Kiểm tra và chứng minh cơ chế đồng thuận (Consensus) và sao chép (Replication)
// Chạy trong mongosh: mongosh --port 27017 /scripts/demo_consensus.js
// ==============================================================================

print("\n======================================================================");
print("     DEMO CƠ CHẾ ĐỒNG THUẬN (CONSENSUS) VÀ NHÂN BẢN (REPLICATION)     ");
print("                    MONGODB REPLICA SET (3 NODES)                     ");
print("======================================================================\n");

// 1. Kiểm tra trạng thái Replica Set
const status = rs.status();
if (status.ok !== 1) {
  print("[LỖI] Replica Set chưa sẵn sàng hoặc chưa được khởi tạo!");
  quit(1);
}

print("1. [THÔNG TIN ĐỒNG THUẬN CỤM (CONSENSUS METADATA)]");
print(`- Tên Replica Set: ${status.set}`);
print(`- Bầu cử Term hiện tại (Election Term): ${status.term}`);
print(`- Số lượng node thành viên: ${status.members.length}`);
print(`- Đa số phiếu cần thiết (Quorum/Majority): ${Math.floor(status.members.length / 2) + 1} nodes\n`);

print("2. [DANH SÁCH CÁC NODE VÀ VAI TRÒ HIỆN TẠI]");
status.members.forEach(member => {
  const isSelf = member.self ? " (Node kết nối hiện tại)" : "";
  print(`  * Node [${member._id}] ${member.name}:`);
  print(`    - Trạng thái: ${member.stateStr}${isSelf}`);
  print(`    - Health: ${member.health === 1 ? "ALIVE (1)" : "DOWN (0)"}`);
  print(`    - Uptime: ${member.uptime}s`);
  if (member.optimeDate) {
    print(`    - Thời gian Oplog mới nhất (Sync Point): ${member.optimeDate.toISOString()}`);
  }
  if (member.stateStr === "PRIMARY") {
    print(`    - Bầu cử tại thời điểm: ${member.electionTime ? member.electionTime : "N/A"}`);
  }
  print("");
});

// 2. Demo Ghi dữ liệu với cam kết đồng thuận đa số (writeConcern: "majority")
print("3. [DEMO GHI DỮ LIỆU VỚI CƠ CHẾ ĐỒNG THUẬN ĐA SỐ (MAJORITY CONCERN)]");
print("-> Ghi 1 giao dịch mới yêu cầu xác nhận từ đa số node (ít nhất 2/3 nodes)...");

const testDb = db.getSiblingDB("blockchain_db");
const transactionData = {
  txId: "tx_" + Date.now(),
  sender: "Alice",
  receiver: "Bob",
  amount: 25.5,
  timestamp: new Date(),
  description: "Giao dịch kiểm tra cơ chế đồng thuận phân tán"
};

try {
  const writeRes = testDb.transactions.insertOne(transactionData, {
    writeConcern: { w: "majority", wtimeout: 5000 }
  });
  print(`[THÀNH CÔNG] Dữ liệu đã được ghi và đạt đồng thuận Majority!`);
  print(`  - Inserted ID: ${writeRes.insertedId}`);
  print(`  - Transaction ID: ${transactionData.txId}`);
} catch (e) {
  print(`[THẤT BẠI] Lỗi khi ghi dữ liệu: ${e.message}`);
}

// 3. Đọc lại dữ liệu để xác nhận
print("\n4. [KIỂM TRA DỮ LIỆU ĐÃ LƯU TRÊN DATABASE]");
const latestTx = testDb.transactions.find().sort({ timestamp: -1 }).limit(1).toArray();
if (latestTx.length > 0) {
  print("Dữ liệu bản ghi mới nhất:");
  print(JSON.stringify(latestTx[0], null, 2));
}

print("\n======================================================================");
print("KẾT LUẬN:");
print("- Thuật toán đồng thuận (Raft variant) đảm bảo chỉ duy nhất 1 PRIMARY được bầu.");
print("- WriteConcern 'majority' đảm bảo dữ liệu ghi thành công khi được ghi nhận bởi >= 2/3 node.");
print("======================================================================\n");
