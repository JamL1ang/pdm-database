-- ============================================================
-- 04_privileges.sql  数据库用户、角色与授权
-- C1 产品数据管理（PDM）数字化系统 | MySQL 8.0.16+
-- 执行顺序：01 → 02 → 03 → 04 → 05 → 06
--
-- 两个层次的权限（相互呼应，不要混淆）：
--   ① 应用级：sys_role / sys_user / doc_permission 三张业务表，
--      控制「某角色能读哪类设计文档」，见 05 数据与 06 权限查询；
--   ② 数据库级：本文件的 MySQL 账号与 GRANT，
--      控制「谁能连库、能对哪些表/视图做 SELECT/INSERT/UPDATE」。
-- 依赖：01 的表、03 的视图都已存在。本文件可重复执行（幂等）。
-- 需要用 root 或具备 CREATE USER / GRANT 权限的账号执行。
-- ============================================================

USE pdm_db;

-- ---------- 4.1 建立四类业务账号 ----------
CREATE USER IF NOT EXISTS 'pdm_design'@'localhost' IDENTIFIED BY 'Pdm@Design2026';
CREATE USER IF NOT EXISTS 'pdm_buyer'@'localhost'  IDENTIFIED BY 'Pdm@Buyer2026';
CREATE USER IF NOT EXISTS 'pdm_qc'@'localhost'     IDENTIFIED BY 'Pdm@Qc2026';
CREATE USER IF NOT EXISTS 'pdm_guest'@'localhost'  IDENTIFIED BY 'Pdm@Guest2026';

-- ---------- 4.2 建立只读角色（MySQL 8.0 ROLE） ----------
CREATE ROLE IF NOT EXISTS 'r_pdm_readonly';
GRANT SELECT ON pdm_db.* TO 'r_pdm_readonly';

-- ---------- 4.3 设计工程师：全库只读 + 可维护文档与版本 ----------
GRANT SELECT ON pdm_db.* TO 'pdm_design'@'localhost';
GRANT SELECT, INSERT, UPDATE ON pdm_db.document        TO 'pdm_design'@'localhost';
GRANT SELECT, INSERT, UPDATE ON pdm_db.product_version TO 'pdm_design'@'localhost';

-- ---------- 4.4 采购员：只能看供应商与供货相关表，看不到设计文档 ----------
GRANT SELECT ON pdm_db.supplier               TO 'pdm_buyer'@'localhost';
GRANT SELECT ON pdm_db.component             TO 'pdm_buyer'@'localhost';
GRANT SELECT ON pdm_db.material              TO 'pdm_buyer'@'localhost';
GRANT SELECT ON pdm_db.component_supplier    TO 'pdm_buyer'@'localhost';
GRANT SELECT ON pdm_db.material_supplier     TO 'pdm_buyer'@'localhost';
GRANT SELECT ON pdm_db.batch_component_source TO 'pdm_buyer'@'localhost';
GRANT SELECT ON pdm_db.batch_material_source  TO 'pdm_buyer'@'localhost';

-- ---------- 4.5 质检员：只给溯源视图与单品表，权限最小化 ----------
GRANT SELECT ON pdm_db.product_instance TO 'pdm_qc'@'localhost';
GRANT SELECT ON pdm_db.v_serial_trace  TO 'pdm_qc'@'localhost';
GRANT SELECT ON pdm_db.v_batch_supply_detail TO 'pdm_qc'@'localhost';

-- ---------- 4.6 访客：通过角色一次性获得全库只读 ----------
GRANT 'r_pdm_readonly' TO 'pdm_guest'@'localhost';
SET DEFAULT ROLE ALL TO 'pdm_guest'@'localhost';

-- ---------- 4.7 授权回收示例（需要时解开注释） ----------
-- REVOKE INSERT, UPDATE ON pdm_db.document FROM 'pdm_design'@'localhost';
-- REVOKE 'r_pdm_readonly' FROM 'pdm_guest'@'localhost';

-- ---------- 4.8 验证授权结果 ----------
SHOW GRANTS FOR 'pdm_design'@'localhost';
SHOW GRANTS FOR 'pdm_qc'@'localhost';
SHOW GRANTS FOR 'pdm_guest'@'localhost';

-- ---------- 4.9 附：切换账号验证权限（在命令行里执行） ----------
-- mysql -u pdm_qc -p pdm_db
-- SELECT * FROM v_serial_trace WHERE `出厂序列号` = 'SN0001';  -- 应当成功
-- SELECT * FROM document;                                      -- 应当报 ERROR 1142 权限不足
