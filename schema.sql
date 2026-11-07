-- ============================================================
-- PDM 产品数据管理（PDM）数字化系统 —— 简化数据库模式设计
-- 建表 + 示例数据 + 查询，一份直接跑通（MySQL 8.x）
--
-- v2 修订：
--   1. 增加 product_version（产品迭代版本）实体，文档挂版本而非产品
--   2. 增加权限扩展（sys_role / sys_user / doc_permission）
--   3. 补全示例数据：多家供货、多批次供货源、多个产品的 BOM 与文档
--   4. 供应商统计改为三种方式，并修复原统计的笛卡尔积问题
--   5. 溯源查询合并部件层与材料层，一次看全
-- ============================================================

CREATE DATABASE IF NOT EXISTS pdm_db CHARACTER SET utf8mb4;
USE pdm_db;

-- ---------- 删除旧表（方便重复运行：严格按 子表 -> 父表 顺序） ----------
DROP TABLE IF EXISTS doc_permission;
DROP TABLE IF EXISTS sys_user;
DROP TABLE IF EXISTS sys_role;
DROP TABLE IF EXISTS batch_material_source;
DROP TABLE IF EXISTS batch_component_source;
DROP TABLE IF EXISTS product_instance;
DROP TABLE IF EXISTS batch;
DROP TABLE IF EXISTS material_supplier;
DROP TABLE IF EXISTS component_supplier;
DROP TABLE IF EXISTS supplier;
DROP TABLE IF EXISTS component_material;
DROP TABLE IF EXISTS product_component;
DROP TABLE IF EXISTS material;
DROP TABLE IF EXISTS component;
DROP TABLE IF EXISTS document;
DROP TABLE IF EXISTS product_version;
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS product_type;

-- ============================================================
-- 一、建表
-- ============================================================

-- ---------- 1.1 产品与文档（题目 1、2） ----------
CREATE TABLE product_type (
    type_id   INT PRIMARY KEY,
    type_name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE product (
    product_id INT PRIMARY KEY,
    type_id    INT NOT NULL,
    series     VARCHAR(50),
    model      VARCHAR(100),
    price      DECIMAL(12,2),
    FOREIGN KEY (type_id) REFERENCES product_type(type_id)
);

-- 产品的迭代版本：一个型号可以有 v1.0 / v1.1 / ... 多次改版
CREATE TABLE product_version (
    version_id   INT PRIMARY KEY,
    product_id   INT NOT NULL,
    version_no   VARCHAR(20) NOT NULL,
    release_date DATE,
    change_note  VARCHAR(200),
    UNIQUE (product_id, version_no),
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

-- 文档挂在"版本"上；doc_rev 是文档自身的修订号，与产品版本是两个概念
CREATE TABLE document (
    doc_id      INT PRIMARY KEY,
    version_id  INT NOT NULL,
    doc_type    VARCHAR(20) NOT NULL,
    doc_rev     VARCHAR(20) NOT NULL,
    title       VARCHAR(200),
    file_path   VARCHAR(500),
    author      VARCHAR(50),
    update_date DATE,
    UNIQUE (version_id, doc_type, doc_rev),
    FOREIGN KEY (version_id) REFERENCES product_version(version_id)
);

-- ---------- 1.2 部件、材料与两层 BOM（题目 3、4、5、6） ----------
-- source_type：采购 = 外部采购成品件；自产 = 采购材料后自行生产
CREATE TABLE component (
    component_id   INT PRIMARY KEY,
    component_code VARCHAR(50) NOT NULL UNIQUE,
    component_name VARCHAR(100) NOT NULL,
    source_type    CHAR(4) NOT NULL,
    CHECK (source_type IN ('采购', '自产'))
);

CREATE TABLE material (
    material_id   INT PRIMARY KEY,
    material_code VARCHAR(50) NOT NULL UNIQUE,
    material_name VARCHAR(100) NOT NULL
);

-- 产品 <-> 部件，M:N，中间表带用量
CREATE TABLE product_component (
    product_id   INT NOT NULL,
    component_id INT NOT NULL,
    quantity     INT NOT NULL,
    PRIMARY KEY (product_id, component_id),
    FOREIGN KEY (product_id) REFERENCES product(product_id),
    FOREIGN KEY (component_id) REFERENCES component(component_id)
);

-- 自产部件 <-> 材料，M:N，中间表带用量（如接线 = 接头 + 连接线）
CREATE TABLE component_material (
    component_id INT NOT NULL,
    material_id  INT NOT NULL,
    quantity     DECIMAL(12,4) NOT NULL,
    PRIMARY KEY (component_id, material_id),
    FOREIGN KEY (component_id) REFERENCES component(component_id),
    FOREIGN KEY (material_id) REFERENCES material(material_id)
);

-- ---------- 1.3 供应商与可供清单（题目 7） ----------
CREATE TABLE supplier (
    supplier_id   INT PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact       VARCHAR(50),
    phone         VARCHAR(20),
    address       VARCHAR(200)
);

-- "谁能供什么"：部件与供应商 M:N，带报价
CREATE TABLE component_supplier (
    component_id INT NOT NULL,
    supplier_id  INT NOT NULL,
    supply_price DECIMAL(12,2),
    PRIMARY KEY (component_id, supplier_id),
    FOREIGN KEY (component_id) REFERENCES component(component_id),
    FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id)
);

-- 材料与供应商也是 M:N
CREATE TABLE material_supplier (
    material_id  INT NOT NULL,
    supplier_id  INT NOT NULL,
    supply_price DECIMAL(12,2),
    PRIMARY KEY (material_id, supplier_id),
    FOREIGN KEY (material_id) REFERENCES material(material_id),
    FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id)
);

-- ---------- 1.4 生产批次与追溯（题目 8、9，本题核心） ----------
CREATE TABLE batch (
    batch_id        INT PRIMARY KEY,
    batch_no        VARCHAR(50) NOT NULL UNIQUE,
    product_id      INT NOT NULL,
    production_date DATE,
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

-- 单台出厂产品：序列号挂在这里，而不是挂在"型号"上
CREATE TABLE product_instance (
    serial_no       VARCHAR(50) PRIMARY KEY,
    product_id      INT NOT NULL,
    batch_id        INT NOT NULL,
    production_date DATE,
    FOREIGN KEY (product_id) REFERENCES product(product_id),
    FOREIGN KEY (batch_id) REFERENCES batch(batch_id)
);

-- "这一批实际用了谁家的"：批次 + 物料 -> 唯一供应商
-- 复合外键保证：只能从已登记的可供清单里选供应商，不能凭空指定
CREATE TABLE batch_component_source (
    batch_id     INT NOT NULL,
    component_id INT NOT NULL,
    supplier_id  INT NOT NULL,
    PRIMARY KEY (batch_id, component_id),
    FOREIGN KEY (batch_id) REFERENCES batch(batch_id),
    FOREIGN KEY (component_id, supplier_id)
        REFERENCES component_supplier(component_id, supplier_id)
);

CREATE TABLE batch_material_source (
    batch_id    INT NOT NULL,
    material_id INT NOT NULL,
    supplier_id INT NOT NULL,
    PRIMARY KEY (batch_id, material_id),
    FOREIGN KEY (batch_id) REFERENCES batch(batch_id),
    FOREIGN KEY (material_id, supplier_id)
        REFERENCES material_supplier(material_id, supplier_id)
);

-- ---------- 1.5 扩展：权限信息（呼应题目总述，简化实现） ----------
CREATE TABLE sys_role (
    role_id   INT PRIMARY KEY,
    role_name VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE sys_user (
    user_id  INT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    role_id  INT NOT NULL,
    FOREIGN KEY (role_id) REFERENCES sys_role(role_id)
);

-- 按角色 + 文档类型控制读写，不细化到单份文档（简化）
CREATE TABLE doc_permission (
    role_id   INT NOT NULL,
    doc_type  VARCHAR(20) NOT NULL,
    can_read  TINYINT NOT NULL DEFAULT 0,
    can_write TINYINT NOT NULL DEFAULT 0,
    PRIMARY KEY (role_id, doc_type),
    FOREIGN KEY (role_id) REFERENCES sys_role(role_id)
);

-- ============================================================
-- 二、示例数据
-- 注意插入顺序：父表 -> 子表；批次供货表依赖可供清单，必须最后插
-- ============================================================

INSERT INTO product_type VALUES
(1,'手机'), (2,'无人机'), (3,'扫地机');

INSERT INTO product VALUES
(1, 1, 'X系列',     'X100',     4999.00),
(2, 1, 'X系列',     'X200 Pro', 6999.00),
(3, 2, 'Mini系列',  'AirMini',  2999.00);

-- 产品版本：X100 有两次迭代，另外两个型号各一个首发版本
INSERT INTO product_version VALUES
(1, 1, 'v1.0', '2026-01-10', 'X100 首发版本'),
(2, 1, 'v1.1', '2026-02-15', 'X100 改版：摄像头与散热调整'),
(3, 2, 'v1.0', '2026-02-01', 'X200 Pro 首发'),
(4, 3, 'v1.0', '2026-02-20', 'AirMini 首发');

-- 文档挂在版本上：同一个版本下有多种文档类型
INSERT INTO document VALUES
(1, 1, '设计说明书', 'R1', 'X100 设计说明书 v1.0', '/docs/x100/v10/spec.pdf',   '张三', '2026-01-10'),
(2, 1, '设计图',     'R1', 'X100 结构设计图 v1.0', '/docs/x100/v10/draw.pdf',   '李四', '2026-01-12'),
(3, 2, '设计说明书', 'R1', 'X100 设计说明书 v1.1', '/docs/x100/v11/spec.pdf',   '张三', '2026-02-15'),
(4, 2, '设计图',     'R1', 'X100 结构设计图 v1.1', '/docs/x100/v11/draw.pdf',   '李四', '2026-02-16'),
(5, 2, 'CAD文件',    'R1', 'X100 主板 CAD v1.1',   '/docs/x100/v11/board.step', '王工', '2026-02-17'),
(6, 3, '设计说明书', 'R1', 'X200 Pro 设计说明书',  '/docs/x200/spec.pdf',       '张三', '2026-02-01'),
(7, 3, '设计图',     'R1', 'X200 Pro 结构设计图',  '/docs/x200/draw.pdf',       '李四', '2026-02-03'),
(8, 4, '设计说明书', 'R1', 'AirMini 设计说明书',   '/docs/airmini/spec.pdf',    '张三', '2026-02-20');

INSERT INTO component VALUES
(1,'C001','外壳',  '采购'),
(2,'C002','显示屏','采购'),
(3,'C003','处理器','采购'),
(4,'C004','电池',  '采购'),
(5,'C005','主板',  '自产'),
(6,'C006','接线',  '自产');

INSERT INTO material VALUES
(1,'M001','接头'),
(2,'M002','连接线'),
(3,'M003','PCB板'),
(4,'M004','芯片');

-- 产品 1/2/3 都有 BOM，且共用同一批部件（体现题目 4：同部件用于不同产品）
INSERT INTO product_component VALUES
(1,1,1),(1,2,1),(1,3,1),(1,4,1),(1,5,1),(1,6,2),
(2,1,1),(2,2,1),(2,3,1),(2,4,1),(2,5,1),(2,6,1),
(3,1,1),(3,3,1),(3,4,2),(3,6,1);

-- 只有"自产"部件才有材料构成
INSERT INTO component_material VALUES
(5,3,1),(5,4,2),
(6,1,2),(6,2,1);

INSERT INTO supplier VALUES
(1,'深圳精密模具','王工',   '13800000001','深圳'),
(2,'京东方科技',  '刘经理', '13800000002','北京'),
(3,'高通电子',    '陈经理', '13800000003','上海'),
(4,'宁德新能源',  '赵经理', '13800000004','宁德'),
(5,'立讯精密',    '孙经理', '13800000005','东莞');

-- 【题目 7】两个方向都要有数据：
--   一种部件多家供：外壳(1)、显示屏(2)、电池(4) 各有 2 家；处理器(3) 独家
--   一家供多种：供应商 1 供外壳/电池，供应商 5 供外壳/显示屏
-- 自产部件(5,6)不采购成品，所以不出现在可供清单里，其来源体现在材料层
INSERT INTO component_supplier VALUES
(1,1,50.00),(1,5,52.00),
(2,2,300.00),(2,5,295.00),
(3,3,800.00),
(4,4,100.00),(4,1,105.00);

INSERT INTO material_supplier VALUES
(1,5,0.50),(1,1,0.55),
(2,5,1.00),
(3,1,20.00),(3,5,21.00),
(4,3,200.00),(4,1,210.00);

-- 4 个批次，覆盖 3 个产品；批次号与生产日期保持一致
INSERT INTO batch VALUES
(1,'B20260301',1,'2026-03-01'),
(2,'B20260302',1,'2026-03-02'),
(3,'B20260310',2,'2026-03-10'),
(4,'B20260315',3,'2026-03-15');

INSERT INTO product_instance VALUES
('SN0001',1,1,'2026-03-01'),
('SN0002',1,1,'2026-03-01'),
('SN0003',1,2,'2026-03-02'),
('SN0004',2,3,'2026-03-10'),
('SN0005',2,3,'2026-03-10'),
('SN0006',3,4,'2026-03-15');

-- 【题目 8】批次级锁定供货源：同一批次内每种物料只有一家供应商
-- 批次 1 与批次 2 是同一个产品 X100，但外壳/显示屏换了供应商
--   -> 这正是缺陷溯源的意义：SN0001 和 SN0003 能查出不同的供应商
-- 注意：每一行 (物料, 供应商) 组合必须已存在于上面的可供清单中
INSERT INTO batch_component_source VALUES
(1,1,1),(1,2,2),(1,3,3),(1,4,4),
(2,1,5),(2,2,5),(2,3,3),(2,4,1),
(3,1,1),(3,2,2),(3,3,3),(3,4,4),
(4,1,5),(4,3,3),(4,4,4);

INSERT INTO batch_material_source VALUES
(1,1,5),(1,2,5),(1,3,1),(1,4,3),
(2,1,1),(2,2,5),(2,3,5),(2,4,1),
(3,1,5),(3,2,5),(3,3,1),(3,4,3),
(4,1,5),(4,2,5);

INSERT INTO sys_role VALUES
(1,'设计工程师'), (2,'采购员'), (3,'质检员');

INSERT INTO sys_user VALUES
(1,'zhangsan',1), (2,'lisi',1), (3,'wangwu',2), (4,'zhaoliu',3);

INSERT INTO doc_permission VALUES
(1,'设计说明书',1,1),(1,'设计图',1,1),(1,'CAD文件',1,1),
(2,'设计说明书',1,0),(2,'设计图',1,0),(2,'CAD文件',0,0),
(3,'设计说明书',1,0),(3,'设计图',1,0),(3,'CAD文件',1,0);

-- ============================================================
-- 三、查询（对应题目 9）
-- ============================================================

-- ---------- 查询 1：某个产品的设计文档（按迭代版本组织） ----------
SELECT p.model                AS 产品型号,
       pv.version_no          AS 产品版本,
       pv.release_date        AS 版本发布日期,
       d.doc_type             AS 文档类型,
       d.doc_rev              AS 文档修订号,
       d.title                AS 标题,
       d.author               AS 作者,
       d.update_date          AS 更新日期,
       d.file_path            AS 文件路径
FROM product p
JOIN product_version pv ON pv.product_id = p.product_id
JOIN document d         ON d.version_id  = pv.version_id
WHERE p.product_id = 1
ORDER BY pv.release_date, d.doc_type;

-- ---------- 查询 2：供应商供货情况统计（三种统计方式） ----------

-- 2-A 按供应商：统计可供的部件/材料种类数
-- 两张可供清单先各自聚合再 LEFT JOIN，避免原写法把行数相乘（笛卡尔积）
SELECT s.supplier_name                                    AS 供应商,
       COALESCE(c.cnt, 0)                                  AS 可供部件种类数,
       COALESCE(m.cnt, 0)                                  AS 可供材料种类数,
       COALESCE(c.cnt, 0) + COALESCE(m.cnt, 0)            AS 合计物料种类数
FROM supplier s
LEFT JOIN (SELECT supplier_id, COUNT(*) AS cnt FROM component_supplier GROUP BY supplier_id) c
       ON c.supplier_id = s.supplier_id
LEFT JOIN (SELECT supplier_id, COUNT(*) AS cnt FROM material_supplier  GROUP BY supplier_id) m
       ON m.supplier_id = s.supplier_id
ORDER BY 合计物料种类数 DESC, 供应商;

-- 2-B 按物料：统计每种物料有几家可选供应商（体现题目 7 的"多家供货"）
SELECT '部件' AS 物料类型, c.component_name AS 物料名称,
       COUNT(cs.supplier_id) AS 可选供应商数
FROM component c
JOIN component_supplier cs ON cs.component_id = c.component_id
GROUP BY c.component_id, c.component_name
UNION ALL
SELECT '材料', m.material_name, COUNT(ms.supplier_id)
FROM material m
JOIN material_supplier ms ON ms.material_id = m.material_id
GROUP BY m.material_id, m.material_name
ORDER BY 可选供应商数 DESC, 物料类型;

-- 2-C 按批次：统计各批次里每家供应商实际供了多少种物料
-- 与 2-A 的区别：2-A 是"能供什么"，2-C 是"这一批真的用了谁家的"
SELECT b.batch_no AS 批次号, p.model AS 产品型号,
       s.supplier_name AS 实际供应商,
       COUNT(DISTINCT x.item_key) AS 供货物料项数
FROM (
    SELECT batch_id, supplier_id, CONCAT('C', component_id) AS item_key FROM batch_component_source
    UNION ALL
    SELECT batch_id, supplier_id, CONCAT('M', material_id)  AS item_key FROM batch_material_source
) x
JOIN batch b    ON b.batch_id    = x.batch_id
JOIN product p  ON p.product_id  = b.product_id
JOIN supplier s ON s.supplier_id = x.supplier_id
GROUP BY b.batch_no, p.model, s.supplier_name
ORDER BY b.batch_no, 供货物料项数 DESC;

-- ---------- 查询 3：按出厂序列号追溯部件/材料的实际供应商 ----------
-- 思路：序列号 -> 批次 -> 批次供货表，再沿两层 BOM 展开
-- 自产部件本身没有采购供应商，其来源通过"材料层"体现，属正常现象

-- 3-① 部件层
SELECT pi.serial_no AS 出厂序列号, b.batch_no AS 批次号,
       c.component_name AS 部件, c.source_type AS 来源,
       COALESCE(s.supplier_name, '（自产件，见材料层）') AS 供应商
FROM product_instance pi
JOIN batch b              ON b.batch_id     = pi.batch_id
JOIN product_component pc ON pc.product_id  = pi.product_id
JOIN component c          ON c.component_id = pc.component_id
LEFT JOIN batch_component_source bcs
       ON bcs.batch_id = pi.batch_id AND bcs.component_id = pc.component_id
LEFT JOIN supplier s ON s.supplier_id = bcs.supplier_id
WHERE pi.serial_no = 'SN0001'
ORDER BY c.component_id;

-- 3-② 材料层（自产部件用的材料）
SELECT pi.serial_no AS 出厂序列号, b.batch_no AS 批次号,
       m.material_name AS 材料, s.supplier_name AS 供应商
FROM product_instance pi
JOIN batch b               ON b.batch_id      = pi.batch_id
JOIN product_component  pc ON pc.product_id   = pi.product_id
JOIN component_material cm ON cm.component_id = pc.component_id
JOIN material            m ON m.material_id   = cm.material_id
LEFT JOIN batch_material_source bms
       ON bms.batch_id = pi.batch_id AND bms.material_id = cm.material_id
LEFT JOIN supplier s ON s.supplier_id = bms.supplier_id
WHERE pi.serial_no = 'SN0001'
ORDER BY m.material_id;

-- 3-③ 两层合并：一次查出这台机器全部物料的实际供应商
SELECT x.出厂序列号, x.批次号, x.层级, x.物料名称, x.供应商
FROM (
    SELECT pi.serial_no AS 出厂序列号, b.batch_no AS 批次号,
           '部件' AS 层级, c.component_name AS 物料名称,
           COALESCE(s.supplier_name, '（自产件，见材料层）') AS 供应商
    FROM product_instance pi
    JOIN batch b              ON b.batch_id     = pi.batch_id
    JOIN product_component pc ON pc.product_id  = pi.product_id
    JOIN component c          ON c.component_id = pc.component_id
    LEFT JOIN batch_component_source bcs
           ON bcs.batch_id = pi.batch_id AND bcs.component_id = pc.component_id
    LEFT JOIN supplier s ON s.supplier_id = bcs.supplier_id
    UNION ALL
    SELECT pi.serial_no, b.batch_no, '材料', m.material_name,
           COALESCE(sm.supplier_name, '（未登记）')
    FROM product_instance pi
    JOIN batch b               ON b.batch_id      = pi.batch_id
    JOIN product_component  pc ON pc.product_id   = pi.product_id
    JOIN component_material cm ON cm.component_id = pc.component_id
    JOIN material            m ON m.material_id   = cm.material_id
    LEFT JOIN batch_material_source bms
           ON bms.batch_id = pi.batch_id AND bms.material_id = cm.material_id
    LEFT JOIN supplier sm ON sm.supplier_id = bms.supplier_id
) x
WHERE x.出厂序列号 = 'SN0001'
ORDER BY x.层级, x.物料名称;

-- 【动手验证】把上面 3-③ 的 'SN0001' 改成 'SN0003' 再跑一次：
--   同一型号 X100，外壳/显示屏/接头/芯片的供应商会变，因为两台机器分属不同批次。
--   这就是题目所说"探究产品缺陷产生原因"的数据依据。

-- ---------- 扩展查询：某角色能读哪些类型的文档（权限） ----------
SELECT u.username AS 用户, r.role_name AS 角色,
       dp.doc_type AS 文档类型, dp.can_read AS 可读, dp.can_write AS 可写
FROM sys_user u
JOIN sys_role r       ON r.role_id = u.role_id
JOIN doc_permission dp ON dp.role_id = r.role_id
WHERE u.username = 'wangwu'
ORDER BY dp.doc_type;

-- ---------- 附：约束验证（故意执行会报错，可截图放进报告） ----------
-- INSERT INTO product_instance VALUES ('SN0001', 1, 1, '2026-03-01');  -- 违反主键：序列号重复
-- INSERT INTO batch_component_source VALUES (3, 6, 5);                  -- 违反复合外键：自产件"接线"未登记过采购供应商
-- INSERT INTO component VALUES (7,'C007','摄像头','外协');                -- 违反 CHECK：来源只能采购/自产
