# BÀI TẬP 2: TRIỂN KHAI MONGODB REPLICA SET VỚI DOCKER & MÔ PHỎNG CƠ CHẾ ĐỒNG THUẬN (CONSENSUS) VÀ NHÂN BẢN (REPLICATION) 3 NODES

---

## 1. TỔNG QUAN VÀ MỤC TIÊU BÀI TẬP

Bài tập này triển khai một cụm cơ sở dữ liệu phân tán **MongoDB Replica Set** gồm **3 nodes** bằng **Docker** và **Docker Compose**, nhằm mô phỏng và chứng minh:
1. **Docker Containerization**: Xây dựng Docker image siêu nhẹ (lightweight) cài đặt MongoDB Community Server & MongoDB Shell (`mongosh`) từ `debian:bookworm-slim` (chỉ ~30MB base, thay thế Ubuntu nặng nề).
2. **Cơ chế Nhân bản dữ liệu (Data Replication)**: Dữ liệu được ghi vào node PRIMARY và tự động nhân bản (replicate) đồng bộ tới các node SECONDARY thông qua Operation Log (`oplog`).
3. **Cơ chế Đồng thuận phân tán (Distributed Consensus Protocol)**:
   - MongoDB sử dụng biến thể của thuật toán đồng thuận **Raft** (Raft-like consensus).
   - Quy tắc đa số (**Quorum / Majority Rule**): Với cụm $N = 3$ nodes, số phiếu cần thiết để đạt đồng thuận là $\lfloor N/2 \rfloor + 1 = 2$ nodes.
   - Cơ chế giám sát nhịp tim (**Heartbeats**) và phát hiện sự cố (**Failure Detection**).
   - Tự động bầu cử Leader (**Leader Election**) khi node PRIMARY gặp sự cố, đảm bảo tính sẵn sàng cao (**High Availability - HA**).
   - Ngăn chặn phân mảnh mạng (**Split-Brain Prevention**).

> [!NOTE]
> **Tại sao không sử dụng Alpine Linux cho MongoDB Server?**
> - Alpine sử dụng thư viện C tối giản là `musl libc`, trong khi MongoDB phụ thuộc sâu vào GNU C (`glibc`), cơ chế quản lý bộ nhớ và lời gọi hệ thống `fsync()` trên thư mục của công cụ lưu trữ WiredTiger. Việc chạy MongoDB trên Alpine thường xuyên gây crash hoặc hỏng dữ liệu.
> - MongoDB đã chính thức bị gỡ bỏ khỏi kho gói chính thức của Alpine và hãng MongoDB Inc. không phát hành bản build cho Alpine.
> - Vì vậy, giải pháp siêu nhẹ (lightweight) chuẩn mực của ngành chính là **`debian:bookworm-slim`** (base chỉ ~30MB, đây cũng chính là base image mà đội ngũ MongoDB chính thức sử dụng cho image `mongo:7.0` trên Docker Hub).

---

## 2. KIẾN TRÚC HỆ THỐNG (SYSTEM ARCHITECTURE)

```
                       +-----------------------------------+
                       |       Docker Network (Bridge)     |
                       |          "mongo-network"          |
                       +-----------------+-----------------+
                                         |
         +-------------------------------+-------------------------------+
         |                               |                               |
         v                               v                               v
  +--------------+                +--------------+                +--------------+
  |    mongo1    | <===Heartbeat==> |    mongo2    | <===Heartbeat==> |    mongo3    |
  |  (Priority 2)|                |  (Priority 1)|                |  (Priority 1)|
  |   PRIMARY    | <=== Oplog ===>|  SECONDARY   | <=== Oplog ===>|  SECONDARY   |
  |  Port: 27017 |                |  Port: 27018 |                |  Port: 27019 |
  +--------------+                +--------------+                +--------------+
         ^                               ^                               ^
         |                               |                               |
         +-------------------------------+-------------------------------+
                                         | (Chờ 3 node Healthy & gọi rs.initiate)
                                  +--------------+
                                  |  mongo-init  |
                                  | (Init setup) |
                                  +--------------+
```

### Thông số các Node:

| Tên Node | Container Name | Port Máy Host | Port Container | Vai trò ban đầu | Priority | Volume lưu trữ |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Node 1** | `mongo1` | `27017` | `27017` | **PRIMARY** | `2` | `mongo1_data` |
| **Node 2** | `mongo2` | `27018` | `27017` | **SECONDARY** | `1` | `mongo2_data` |
| **Node 3** | `mongo3` | `27019` | `27017` | **SECONDARY** | `1` | `mongo3_data` |
| **Init** | `mongo-init` | *N/A* | *N/A* | *Setup Runner* | *N/A* | Tự tắt sau khi cấu hình xong |

---

## 3. CƠ CHẾ ĐỒNG THUẬN TRONG MONGODB REPLICA SET

### 3.1. Thuật toán bầu cử Raft (Raft Consensus Variant)
MongoDB từ phiên bản 3.2 trở đi sử dụng giao thức đồng thuận tương tự Raft:
- Mỗi chu kỳ bầu cử được đánh dấu bởi một chỉ số tăng dần gọi là **Election Term**.
- Mỗi node thành viên định kỳ gửi tín hiệu kiểm tra sức khỏe (**Heartbeat**) 2 giây một lần tới các node khác.
- Nếu một node SECONDARY không nhận được heartbeat từ PRIMARY trong khoảng thời gian quy định (mặc định 10 giây: `electionTimeoutMillis`), nó sẽ chuyển trạng thái sang **CANDIDATE**, tăng Term và yêu cầu bỏ phiếu.

### 3.2. Điều kiện bầu chọn Leader (Quorum & Election Rule)
Để một node trở thành PRIMARY, node đó phải thỏa mãn 2 điều kiện bắt buộc:
1. **Đạt đa số phiếu tán thành (Quorum / Majority)**:
   $$\text{Quorum} = \lfloor \frac{N}{2} \rfloor + 1$$
   Với cụm 3 node: $\lfloor 3/2 \rfloor + 1 = 2$ phiếu. Cần ít nhất 2 node còn sống và bỏ phiếu đồng ý.
2. **Tính cập nhật của dữ liệu (Oplog Freshness)**: Node ứng viên phải có Operation Log (`oplog`) mới nhất hoặc ít nhất ngang bằng với các node bỏ phiếu khác. Điều này ngăn việc một node có dữ liệu cũ trở thành Leader làm mất dữ liệu của cụm.

### 3.3. Cơ chế ghi dữ liệu có cam kết đồng thuận (`w: "majority"`)
- Khi ghi dữ liệu với tùy chọn `{ writeConcern: { w: "majority" } }`, thao tác ghi chỉ được coi là thành công khi đã được ghi vào bộ nhớ/đĩa của node PRIMARY **và** đã được sao chép sang ít nhất $\lfloor 3/2 \rfloor + 1 = 2$ node.
- Nếu PRIMARY đột ngột gặp sự cố sau khi đã xác nhận `w: "majority"`, dữ liệu này chắc chắn đã tồn tại trên ít nhất 1 node SECONDARY, và node SECONDARY đó sẽ được bầu làm PRIMARY mới mà không bị mất dữ liệu.

---

## 4. CẤU TRÚC THƯ MỤC DỰ ÁN

```
BT2/
├── Dockerfile                  # Định nghĩa Docker Image cài đặt MongoDB 7.0 & mongosh từ Ubuntu 22.04
├── docker-compose.yml          # Cấu hình cụm 3 node MongoDB + service khởi tạo tự động mongo-init
├── scripts/
│   ├── init-replica.js         # Script MongoDB Shell dùng để khởi tạo cụm Replica Set rs0
│   ├── demo_consensus.js       # Script kiểm tra thông tin đồng thuận, Quorum và ghi dữ liệu Majority
│   ├── demo_failover.sh        # Script tự động chạy kịch bản Failover / Leader Election (Linux/macOS/WSL)
│   └── demo_failover.ps1       # Script tự động chạy kịch bản Failover / Leader Election (Windows PowerShell)
└── README.md                   # Hướng dẫn chi tiết lý thuyết và thực hành
```

---

## 5. HƯỚNG DẪN CÀI ĐẶT VÀ KHỞI CHẠY

### 5.1. Yêu cầu hệ thống
- Đã cài đặt Docker và Docker Compose (hoặc Docker Desktop).

### 5.2. Khởi chạy toàn bộ cụm
Mở terminal tại thư mục `BT2/` và chạy lệnh:

```bash
docker compose up -d --build
```

Docker Compose sẽ:
1. Xây dựng Docker image `custom-mongo:7.0` từ `Dockerfile` (cài đặt Ubuntu + MongoDB 7.0 + mongosh).
2. Khởi tạo 3 container `mongo1`, `mongo2`, `mongo3` kết nối vào mạng `mongo-network`.
3. Khi cả 3 container vượt qua bài kiểm tra sức khỏe (`healthcheck`), container `mongo-init` sẽ tự động chạy script `init-replica.js` để thiết lập Replica Set `rs0`.

### 5.3. Kiểm tra trạng thái khởi tạo
Xem log của container cấu hình `mongo-init`:
```bash
docker logs mongo-init
```
Kết quả hiển thị:
```text
[INIT] Kết quả gọi rs.initiate(): {"ok":1}
[SUCCESS] Replica Set đã thiết lập thành công!
[SUCCESS] Node PRIMARY được đồng thuận bầu chọn: mongo1:27017
```

---

## 6. KỊCH BẢN THỰC NGHIỆM VÀ CHỨNG MINH ĐỒNG THUẬN

Có 2 cách thực hiện: **Chạy script tự động** hoặc **Thao tác thủ công từng bước**.

### CÁCH 1: CHẠY SCRIPT DEMO TỰ ĐỘNG

- **Trên Windows PowerShell**:
  ```powershell
  cd scripts
  .\demo_failover.ps1
  ```
- **Trên Linux / macOS / Git Bash / WSL**:
  ```bash
  cd scripts
  chmod +x demo_failover.sh
  ./demo_failover.sh
  ```

---

### CÁCH 2: THAO TÁC THỦ CÔNG TỪNG BƯỚC

#### Bước 1: Kiểm tra cấu hình cụm và trạng thái Đồng thuận (Consensus Topology)
Truy cập vào shell MongoDB của `mongo1`:
```bash
docker exec -it mongo1 mongosh --eval "rs.status()"
```
*Quan sát:*
- `set`: `"rs0"`
- `term`: Số nguyên đại diện cho chu kỳ bầu cử (Election Term hiện tại).
- `members`: Danh sách 3 node, trong đó `mongo1` có `stateStr: "PRIMARY"`, `mongo2` và `mongo3` có `stateStr: "SECONDARY"`.

Hoặc chạy script kiểm tra nhanh:
```bash
docker exec -it mongo1 mongosh /scripts/demo_consensus.js
```

---

#### Bước 2: Ghi dữ liệu vào node PRIMARY với cam kết đồng thuận đa số (`writeConcern: majority`)
Kết nối vào `mongo1` (PRIMARY):
```bash
docker exec -it mongo1 mongosh
```
Trong `mongosh`:
```javascript
use blockchain_db

// Ghi dữ liệu giao dịch yêu cầu đa số (ít nhất 2 node xác nhận)
db.blocks.insertOne(
  {
    index: 1,
    hash: "0x89abcdef12345678",
    data: "Khoi du lieu khoi tao - Ghi vao Primary mongo1",
    timestamp: new Date()
  },
  { writeConcern: { w: "majority", wtimeout: 5000 } }
);

// Đọc lại để kiểm tra
db.blocks.find();
exit;
```

---

#### Bước 3: Kiểm tra nhân bản dữ liệu (Replication) trên node SECONDARY
Kết nối vào `mongo2` (SECONDARY) qua cổng `27018`:
```bash
docker exec -it mongo2 mongosh
```
Trong `mongosh`:
```javascript
use blockchain_db

// Mặc định MongoDB không cho phép đọc trực tiếp trên Secondary để đảm bảo nhất quán.
// Ta cho phép đọc từ Secondary bằng lệnh:
db.getMongo().setReadPref("secondary");

// Đọc dữ liệu: Dữ liệu từ mongo1 đã được tự động nhân bản sang mongo2 qua Oplog!
db.blocks.find();
exit;
```

---

#### Bước 4: Giả lập sự cố node Leader (Fault Tolerance & Leader Election)
Đánh sập node `mongo1` (Primary):
```bash
docker stop mongo1
```

*Hiện tượng diễn ra ở tầng phân tán:*
- `mongo2` và `mongo3` không còn nhận được nhịp tim (heartbeat) từ `mongo1`.
- Sau 10 giây (`electionTimeoutMillis`), một trong hai node sẽ chuyển sang trạng thái CANDIDATE, tăng Term và bắt đầu tiến trình bầu cử (Election).
- Số node còn sống là $2 / 3$, đạt điều kiện Majority ($2 \ge 2$). Do đó, một node mới (`mongo2` hoặc `mongo3`) sẽ nhận đủ 2 phiếu và được bầu làm **PRIMARY mới**.

Kiểm tra kết quả bầu cử từ `mongo2`:
```bash
docker exec -it mongo2 mongosh --eval "rs.status().members.forEach(m => print(m.name + ' => ' + m.stateStr + ' (Health: ' + m.health + ')'))"
```
*Kết quả:*
```text
mongo1:27017 => (not reachable/down) (Health: 0)
mongo2:27017 => PRIMARY (Health: 1)   <--- Đã được đồng thuận bầu lên làm Leader mới!
mongo3:27017 => SECONDARY (Health: 1)
```

---

#### Bước 5: Tiếp tục ghi dữ liệu trên Leader mới
Kết nối vào Leader mới (ví dụ `mongo2`):
```bash
docker exec -it mongo2 mongosh
```
Trong `mongosh`:
```javascript
use blockchain_db

db.blocks.insertOne(
  {
    index: 2,
    hash: "0xabcdef9876543210",
    data: "Khoi du lieu ghi tren Leader moi trong khi mongo1 dang bi sap",
    timestamp: new Date()
  },
  { writeConcern: { w: "majority", wtimeout: 5000 } }
);

db.blocks.find();
exit;
```
*Nhận xét:* Dịch vụ vẫn hoạt động bình thường, ghi dữ liệu thành công vì $2/3$ node vẫn thỏa mãn cam kết `majority`.

---

#### Bước 6: Phục hồi node cũ (`mongo1`) và tự động đồng bộ lại
Khởi động lại `mongo1`:
```bash
docker start mongo1
```
Chờ 5 giây rồi kiểm tra lại trạng thái cụm:
```bash
docker exec -it mongo2 mongosh --eval "rs.status().members.forEach(m => print(m.name + ' => ' + m.stateStr))"
```
*Kết quả:*
- `mongo1` đã sống lại nhưng **không cướp lại quyền PRIMARY**, mà tự động gia nhập với vai trò **SECONDARY**.
- `mongo1` tự động đọc Oplog từ PRIMARY mới để đồng bộ khối dữ liệu `index: 2` còn thiếu.

Kiểm tra trên `mongo1`:
```bash
docker exec -it mongo1 mongosh
```
```javascript
use blockchain_db
db.getMongo().setReadPref("secondary");
db.blocks.find(); // Đã nhận đủ cả 2 khối dữ liệu index: 1 và index: 2!
exit;
```

---

#### Bước 7: Chứng minh cơ chế chống phân mảnh (Split-Brain Prevention) khi mất Quorum
Giả sử có thêm 1 node bị ngắt kết nối (ví dụ `mongo3`), tức là cụm chỉ còn lại duy nhất 1 node hoạt động:
```bash
docker stop mongo3
docker stop mongo1
```
Lúc này chỉ còn lại `mongo2` sống sót:
- Số node còn sống: $1 / 3$.
- Quorum yêu cầu: $2$ nodes.
- Vì $1 < 2$, `mongo2` **tự động hạ cấp từ PRIMARY xuống SECONDARY** và từ chối mọi thao tác ghi dữ liệu mới.
- Điều này chứng minh thuật toán đồng thuận bảo vệ cụm khỏi hiện tượng **Split-Brain** (hai phân vùng mạng độc lập cùng tự nhận mình là Leader).

---

## 7. CHỨNG MINH: USER VẪN TIẾP TỤC GHI ĐƯỢC DỮ LIỆU KHI LEADER BỊ LỖI

### 7.1. Nguyên lý hoạt động ở tầng Client & Driver
Khi một ứng dụng/người dùng tương tác với cụm MongoDB Replica Set:
1. **Chuỗi kết nối thông minh (Replica Set URI)**:
   ```text
   mongodb://mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=rs0&retryWrites=true
   ```
   Client không gắn cứng vào một IP/port duy nhất của Leader mà kết nối tới toàn bộ các node.
2. **Server Discovery and Monitoring (SDAM)**: Client Driver liên tục theo dõi nhịp đập của cụm và tự động định vị node nào đang nắm giữ vai trò `PRIMARY`.
3. **Cơ chế Retry Writes (`retryWrites=true`)**: Khi một thao tác ghi gửi tới Leader đúng thời điểm Leader bị crash:
   - Driver phát hiện sự cố mạng và tạm hoãn lệnh ghi.
   - Các node còn lại tổ chức bầu cử Leader mới (diễn ra trong 2-5 giây).
   - Driver tự động phát hiện Leader mới và thử lại (retry) lệnh ghi thành công mà người dùng không cần can thiệp!

### 7.2. Kịch bản chạy thực nghiệm

#### Cách 1: Chạy script demo tự động
- **Trên Windows PowerShell**:
  ```powershell
  cd scripts
  .\demo_leader_failure_write.ps1
  ```
- **Trên Linux / macOS / Git Bash**:
  ```bash
  cd scripts
  chmod +x demo_leader_failure_write.sh
  ./demo_leader_failure_write.sh
  ```
- **Bằng Python (mô phỏng ứng dụng thực tế)**:
  ```bash
  pip install pymongo
  python scripts/client_resilient_write.py
  ```

#### Cách 2: Thao tác thủ công từng bước

1. **Ghi giao dịch #1 vào Replica Set**:
   ```bash
   docker exec -it mongo2 mongosh "mongodb://mongo1:27017,mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --eval "
     db.orders.insertOne({ id: 1, note: 'Ghi khi Leader ban dau con song' }, { writeConcern: { w: 'majority' } })
   "
   ```

2. **Giả lập sự cố: Đánh sập Leader hiện tại (`mongo1`)**:
   ```bash
   docker stop mongo1
   ```

3. **Chờ 5 giây** để cụm tổ chức bầu cử Leader mới (ví dụ `mongo2` hoặc `mongo3` trở thành Leader mới).

4. **Thực hiện Ghi tiếp giao dịch #2 (khi Leader cũ `mongo1` VẪN ĐANG CHẾT)**:
   ```bash
   docker exec -it mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0&retryWrites=true" --eval "
     db.orders.insertOne({ id: 2, note: 'GHI THANH CONG KHI LEADER BAN DAU DANG SAP' }, { writeConcern: { w: 'majority' } })
   "
   ```
   *Kết quả:* Lệnh ghi **thành công 100%**! Leader mới tiếp nhận và ghi nhận vào Oplog.

5. **Kiểm tra dữ liệu**:
   ```bash
   docker exec -it mongo2 mongosh "mongodb://mongo2:27017,mongo3:27017/blockchain_db?replicaSet=rs0" --eval "
     db.orders.find()
   "
   ```
   *Kết quả:* Toàn bộ dữ liệu (cả đơn #1 và đơn #2) đều được bảo toàn nguyên vẹn.

---

## 8. DỌN DẸP MÔI TRƯỜNG (CLEANUP)

Khi hoàn thành bài tập, xóa các container và volume dữ liệu bằng lệnh:
```bash
docker compose down -v
```

