-- ============================================================
-- 01_schema.sql  建库 + 建表（18 张表）
-- C1 产品数据管理（PDM）数字化系统 | MySQL 8.0.16+
-- 执行顺序：01 → 02 → 03 → 04 → 05 → 06
-- 本文件开头会 DROP 旧表，可反复运行；DROP 顺序为 子表→父表
-- ============================================================

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
