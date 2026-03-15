# TMCP Infra - Gap Analysis vận hành theo System Design

Tài liệu này tổng hợp các việc cần làm để hệ thống vận hành trơn tru, dựa trên nguyên lý SRE/System Design (reliability, scalability, security, operability), đối chiếu với hiện trạng trong:
- `tmcp-infra/init-cluster.sh`
- `tmcp-infra/pb.yaml`
- `tmcp-infra/tmcp-infra/main.tf`
- `tmcp-infra/tmcp-infra/cloud-init.tftpl`
- `tmcp-gitops/INFRASTRUCTURE.md`

## 1) Tóm tắt hiện trạng

- Bootstrap local cluster đã có: script tạo VM Multipass + cài K3s.
- Có hướng Infrastructure as Code bằng Terraform cho Multipass + ArgoCD + Vault.
- Có GitOps stack ở `tmcp-gitops`, nhưng `tmcp-infra` vẫn rất tối giản (README gần như trống).
- Trong `tmcp-infra/pb.yaml` mới có 1 app PocketBase, 1 replica, PVC 1Gi, chưa có hardening và operational guardrails đầy đủ.

Kết luận nhanh: đã có nền tảng để chạy, nhưng chưa đủ maturity để vận hành ổn định khi có tải, lỗi, sự cố, hay luân chuyển phiên bản.

## 2) Khoảng trống quan trọng (Gap) và việc cần làm

### A. Reliability và Availability

Gap:
- Chưa định nghĩa SLO/SLI cho từng dịch vụ (PB, bridge, agent, hub, blog).
- Chưa có readiness/liveness/startup probes được chuẩn hóa cho toàn bộ workload.
- Chưa có canary/blue-green hoặc rollback policy rõ ràng trong GitOps flow.
- Single-node K3s và nhiều thành phần single replica dẫn tới SPOF cao.

Việc cần làm:
- Định nghĩa SLO theo user journey:
  - Đăng nhập/admin PB thành công >= 99.5%/30d.
  - API agent p95 latency < 1s trong giờ làm việc.
  - Publish flow thành công >= 99%.
- Chuẩn hóa probes cho tất cả Deployment, timeout/retry có lý do kỹ thuật.
- Bật policy rollback nhanh:
  - ArgoCD auto-sync + rollback checklist.
  - Lưu lại release metadata (ai deploy, khi nào, commit nào).
- Tách local/dev và pre-prod/prod topology:
  - Prod tối thiểu 3 node control/data plane hoặc managed K8s.

### B. Performance và Capacity

Gap:
- Chưa có baseline tải (RPS, concurrent users, queue depth, DB growth).
- Chưa có resource requests/limits và HPA cho workload quan trọng.
- PVC PB 1Gi dễ bị đầy dung lượng, chưa có dung lượng planning.

Việc cần làm:
- Lập capacity model theo 3 mức: hiện tại, +3 tháng, +12 tháng.
- Đặt requests/limits cho từng service, tránh noisy-neighbor.
- Thiết lập HPA cho agent/bridge/hub (theo CPU + custom metrics nếu có).
- Tăng trữ lượng PB và có chính sách quota/cảnh báo dung lượng.

### C. Data Durability, Backup và DR

Gap:
- Chưa thấy chính sách backup/restore dữ liệu PB được tài liệu hóa đầy đủ.
- Chưa có RPO/RTO cam kết và bài test khôi phục định kỳ.
- Vault key handling hiện tại còn phụ thuộc file local (`tmcp_vault_keys.txt`) dẫn tới operational risk.

Việc cần làm:
- Đặt mục tiêu DR:
  - RPO <= 15 phút (hoặc theo nhu cầu business).
  - RTO <= 60 phút cho khôi phục toàn hệ thống.
- Triển khai backup PB (snapshot + offsite copy) theo lịch.
- Viết runbook restore từng bước và test game-day hằng tháng.
- Chuyển secret-unseal strategy sang cơ chế an toàn hơn (KMS/HSM hoặc quy trình split-key có kiểm soát).

### D. Security và Compliance cơ bản

Gap:
- Secret và credential vẫn có dấu hiệu hardcode/nội bộ trong workflow tài liệu.
- Chưa thấy policy mạng K8s (NetworkPolicy) để bảo vệ lateral movement.
- Chưa có image scanning/SBOM/signature verification trong release.
- Chưa có chính sách RBAC least privilege cho người và service accounts được định nghĩa rõ.

Việc cần làm:
- Chuẩn hóa secret lifecycle:
  - Không hardcode token/password trong code/tài liệu runtime.
  - Rotation policy (30/60/90 ngày tùy loại secret).
- Bổ sung NetworkPolicy cho namespace quan trọng (vault, external-secrets, app).
- Bổ sung security gate trong CI:
  - Scan container image (high/critical fail build).
  - Tạo SBOM + ký image.
- Ra ma trận quyền RBAC và đánh giá lại quyền admin cluster.

### E. Observability (Logs, Metrics, Traces)

Gap:
- Chưa có bộ dashboard SLO và alert theo error budget.
- Logs/metrics có dấu hiệu đã có hướng, nhưng chưa thấy bộ tiêu chuẩn đặt tên metric, correlation-id, trace context xuyên suốt.
- Chưa thấy alert routing theo mức độ (P1/P2/P3) + on-call policy.

Việc cần làm:
- Xây monitoring model 3 lớp:
  - Golden signals (latency, traffic, errors, saturation).
  - Business metrics (publish success rate, queue backlog).
  - Platform metrics (node pressure, restart loops, disk usage).
- Chuẩn hóa structured logging JSON + request id.
- Viết alert catalog:
  - Triệu chứng, ngưỡng, owner, hướng xử lý đầu tiên.
- Đặt dashboard cảnh báo sớm cho PB storage và Vault health.

### F. Release Engineering và Change Management

Gap:
- Chưa có policy branch protection/release promotion rõ (dev -> staging -> prod).
- Chưa thấy quality gates bắt buộc trước deploy (integration test, smoke test, migration check).
- Chưa có strategy rollback data migration khi schema thay đổi.

Việc cần làm:
- Thiết lập release pipeline có cổng gate:
  - Unit/integration tests pass.
  - Security scan pass.
  - Smoke test sau deploy pass.
- Định nghĩa release train (hằng ngày/2 lần 1 tuần) và freeze windows.
- Tiến hành migration strategy:
  - Forward-only migration + backup trước migration.
  - Rollback runbook cho tình huống xấu.

### G. Operability và Incident Response

Gap:
- Chưa có bộ runbook vận hành tập trung cho sự cố thường gặp.
- Chưa có quy trình incident command (ai chỉ huy, ai giao tiếp, ai ghi log sự cố).
- Chưa có postmortem template và cơ chế theo dõi action items sau sự cố.

Việc cần làm:
- Tạo bộ runbook tối thiểu:
  - PB không truy cập được.
  - Vault sealed.
  - ArgoCD sync fail do CRD/secret.
  - Ingress route lỗi 404/502.
- Định nghĩa severity model (SEV1..SEV4) + SLA phản hồi.
- Áp dụng blameless postmortem trong 48h sau sự cố nghiêm trọng.

## 3) Ưu tiên thực thi để hệ thống "trơn tru"

### P0 (1-2 tuần) - Bắt buộc

- Chốt SLO/SLI + dashboard căn bản + alert tối thiểu.
- Hoàn thiện backup/restore PB và test restore thật.
- Xóa hardcoded secrets trong quy trình vận hành.
- Chuẩn hóa probes + requests/limits cho workload chính.
- Viết runbook sự cố cốt lõi (PB, Vault, ArgoCD, Ingress).

### P1 (2-6 tuần) - Ổn định hóa

- HPA cho workload có biến động tải.
- Security gates trong CI (scan image, SBOM, policy fail-fast).
- NetworkPolicy và RBAC review theo least privilege.
- Chuẩn release governance: gating, promotion, rollback checklist.

### P2 (6-12 tuần) - Nâng mức sẵn sàng production

- DR drill định kỳ + game-day chaos test nhẹ.
- Multi-node/managed K8s strategy cho production.
- Nâng cấp observability với tracing và error-budget policy.
- Capacity planning 12 tháng + budget hạ tầng.

## 4) Bộ chỉ số cần theo dõi hằng tuần (Ops Weekly)

- Availability theo từng user journey (% thành công).
- Error budget burn rate theo 1h và 6h.
- p95/p99 latency các API trong giờ cao điểm.
- Số lần deployment, tỉ lệ rollback, MTTR sau incident.
- Tăng trưởng dung lượng PB + dự báo ngày cần mở rộng.
- Số lượng secret sắp hết hạn/đã quá hạn rotation.

## 5) Định nghĩa "Done" cho giai đoạn vận hành cơ bản

Hệ thống được xem là vận hành trơn tru khi:
- Có SLO rõ ràng và dashboard hiển thị theo thời gian thực.
- Có backup/restore đã được diễn tập thành công.
- Có runbook sự cố chính và team đã tập dượt.
- Mọi thay đổi lên production đều qua quality/security gates.
- Không còn hardcoded secrets/token trong code và quy trình deploy.

---

Ghi chú:
- Tài liệu này có tính định hướng architecture/operations, không cần sửa code để bắt đầu.
- Có thể dùng tài liệu này làm backlog cho sprint Ops/Platform tiếp theo.
