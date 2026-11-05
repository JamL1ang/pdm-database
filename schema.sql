-- ============================================================
-- PDM 产品数据管理（PDM）数字化系统 —— 简化数据库模式设计
-- 建表 + 示例数据 + 查询，一份直接跑通
-- ============================================================

CREATE DATABASE IF NOT EXISTS pdm_db CHARACTER SET utf8mb4;
USE pdm_db;

-- ---------- 删除旧表（方便重复运行） ----------
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
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS product_type;

-- ---------- 建表 ----------
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

CREATE TABLE document (
    doc_id      INT PRIMARY KEY,
    product_id  INT NOT NULL,
    doc_type    VARCHAR(20) NOT NULL,
    version     VARCHAR(20) NOT NULL,
    title       VARCHAR(200),
    file_path   VARCHAR(500),
    author      VARCHAR(50),
    update_date DATE,
    UNIQUE (product_id, doc_type, version),
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE TABLE component (
    component_id   INT PRIMARY KEY,
    component_code VARCHAR(50) NOT NULL UNIQUE,
    component_name VARCHAR(100) NOT NULL,
    source_type    CHAR(4) NOT NULL
);

CREATE TABLE material (
    material_id   INT PRIMARY KEY,
    material_code VARCHAR(50) NOT NULL UNIQUE,
    material_name VARCHAR(100) NOT NULL
);

CREATE TABLE product_component (
    product_id   INT NOT NULL,
    component_id INT NOT NULL,
    quantity     INT NOT NULL,
    PRIMARY KEY (product_id, component_id),
    FOREIGN KEY (product_id) REFERENCES product(product_id),
    FOREIGN KEY (component_id) REFERENCES component(component_id)
);

CREATE TABLE component_material (
    component_id INT NOT NULL,
    material_id  INT NOT NULL,
    quantity     DECIMAL(12,4) NOT NULL,
    PRIMARY KEY (component_id, material_id),
    FOREIGN KEY (component_id) REFERENCES component(component_id),
    FOREIGN KEY (material_id) REFERENCES material(material_id)
);

CREATE TABLE supplier (
    supplier_id   INT PRIMARY KEY,
    supplier_name VARCHAR(100) NOT NULL,
    contact       VARCHAR(50),
    phone         VARCHAR(20),
    address       VARCHAR(200)
);

CREATE TABLE component_supplier (
    component_id INT NOT NULL,
    supplier_id  INT NOT NULL,
    supply_price DECIMAL(12,2),
    PRIMARY KEY (component_id, supplier_id),
    FOREIGN KEY (component_id) REFERENCES component(component_id),
    FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id)
);

CREATE TABLE material_supplier (
    material_id  INT NOT NULL,
    supplier_id  INT NOT NULL,
    supply_price DECIMAL(12,2),
    PRIMARY KEY (material_id, supplier_id),
    FOREIGN KEY (material_id) REFERENCES material(material_id),
    FOREIGN KEY (supplier_id) REFERENCES supplier(supplier_id)
);

CREATE TABLE batch (
    batch_id        INT PRIMARY KEY,
    batch_no        VARCHAR(50) NOT NULL UNIQUE,
    product_id      INT NOT NULL,
    production_date DATE,
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

CREATE TABLE product_instance (
    serial_no       VARCHAR(50) PRIMARY KEY,
    product_id      INT NOT NULL,
    batch_id        INT NOT NULL,
    production_date DATE,
    FOREIGN KEY (product_id) REFERENCES product(product_id),
    FOREIGN KEY (batch_id) REFERENCES batch(batch_id)
);

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

-- ---------- 示例数据 ----------
INSERT INTO product_type VALUES
(1,'手机'), (2,'无人机'), (3,'扫地机');

INSERT INTO product VALUES
(1, 1, 'X系列', 'X100', 4999.00),
(2, 1, 'X系列', 'X200 Pro', 6999.00),
(3, 2, 'Mini系列', 'AirMini', 2999.00);

INSERT INTO document VALUES
(1, 1, '设计说明书', 'v1.0', 'X100设计说明书', '/docs/x100/spec_v1.pdf', '张三', '2026-01-10'),
(2, 1, '设计说明书', 'v1.1', 'X100设计说明书', '/docs/x100/spec_v1.1.pdf', '张三', '2026-02-15'),
(3, 1, '设计图',     'v1.0', 'X100结构设计图', '/docs/x100/draw_v1.pdf', '李四', '2026-01-12');

INSERT INTO component VALUES
(1,'C001','外壳','采购'),
(2,'C002','显示屏','采购'),
(3,'C003','处理器','采购'),
(4,'C004','电池','采购'),
(5,'C005','主板','自产'),
(6,'C006','接线','自产');

INSERT INTO material VALUES
(1,'M001','接头'),
(2,'M002','连接线'),
(3,'M003','PCB板'),
(4,'M004','芯片');

INSERT INTO product_component VALUES
(1,1,1),(1,2,1),(1,3,1),(1,4,1),(1,5,1),(1,6,2);

INSERT INTO component_material VALUES
(5,3,1),(5,4,2),
(6,1,2),(6,2,1);

INSERT INTO supplier VALUES
(1,'深圳精密模具','王工','13800000001','深圳'),
(2,'京东方科技','刘经理','13800000002','北京'),
(3,'高通电子','陈经理','13800000003','上海'),
(4,'宁德新能源','赵经理','13800000004','宁德'),
(5,'立讯精密','孙经理','13800000005','东莞');

INSERT INTO component_supplier VALUES
(1,1,50.00),(2,2,300.00),(3,3,800.00),(4,4,100.00);

INSERT INTO material_supplier VALUES
(1,5,0.50),(2,5,1.00),(3,1,20.00),(4,3,200.00);

INSERT INTO batch VALUES
(1,'B20260101',1,'2026-03-01'),
(2,'B20260102',1,'2026-03-02');

INSERT INTO product_instance VALUES
('SN0001',1,1,'2026-03-01'),
('SN0002',1,1,'2026-03-01'),
('SN0003',1,2,'2026-03-02');

INSERT INTO batch_component_source VALUES
(1,1,1),(1,2,2),(1,3,3),(1,4,4);

INSERT INTO batch_material_source VALUES
(1,1,5),(1,2,5),(1,3,1),(1,4,3);

-- ---------- 查询 ----------
-- 查询1：某个产品的设计文档信息
SELECT doc_type, version, title, author, update_date, file_path
FROM document
WHERE product_id = 1
ORDER BY doc_type, version;

-- 查询2：供应商供货情况统计（每个供应商供了多少种）
SELECT s.supplier_name,
       COUNT(DISTINCT cs.component_id) AS 部件种类数,
       COUNT(DISTINCT ms.material_id)  AS 材料种类数
FROM supplier s
LEFT JOIN component_supplier cs ON cs.supplier_id = s.supplier_id
LEFT JOIN material_supplier  ms ON ms.supplier_id  = s.supplier_id
GROUP BY s.supplier_id, s.supplier_name;

-- 查询3：追溯某产品（序列号）的部件/材料供应商
-- 3-① 部件层
SELECT pi.serial_no AS 出厂序列号, c.component_name AS 部件, s.supplier_name AS 供应商
FROM product_instance pi
JOIN product_component pc ON pc.product_id = pi.product_id
JOIN component c          ON c.component_id = pc.component_id
LEFT JOIN batch_component_source bcs
       ON bcs.batch_id = pi.batch_id AND bcs.component_id = pc.component_id
LEFT JOIN supplier s ON s.supplier_id = bcs.supplier_id
WHERE pi.serial_no = 'SN0001';

-- 3-② 材料层（自产部件用的材料）
SELECT pi.serial_no AS 出厂序列号, m.material_name AS 材料, sm.supplier_name AS 供应商
FROM product_instance pi
JOIN product_component  pc ON pc.product_id = pi.product_id
JOIN component_material cm ON cm.component_id = pc.component_id
JOIN material           m  ON m.material_id = cm.material_id
LEFT JOIN batch_material_source bms
       ON bms.batch_id = pi.batch_id AND bms.material_id = cm.material_id
LEFT JOIN supplier sm ON sm.supplier_id = bms.supplier_id
WHERE pi.serial_no = 'SN0001';