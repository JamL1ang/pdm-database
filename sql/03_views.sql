-- ============================================================
-- 03_views.sql  业务视图（5 个）
-- C1 产品数据管理（PDM）数字化系统 | MySQL 8.0.16+
-- 执行顺序：01 → 02 → 03 → 04 → 05 → 06
--
-- 视图的作用：把常用的多表 JOIN 封装成一个「虚拟表」，
--             既能简化业务查询，也能作为权限控制的粒度（见 04）。
-- 注意：MySQL 视图定义不允许 FROM 子句里出现子查询，
--       所以统计类视图一律先用 UNION ALL 造明细视图，再基于它 GROUP BY。
-- 依赖：01 建表完成；04 会给视图授权。可单独重复执行（开头先 DROP）。
-- ============================================================

USE pdm_db;

DROP VIEW IF EXISTS v_supplier_capability;
DROP VIEW IF EXISTS v_serial_trace;
DROP VIEW IF EXISTS v_batch_supply_detail;
DROP VIEW IF EXISTS v_supply_catalog;
DROP VIEW IF EXISTS v_product_documents;

-- ---------- 视图 1：产品 → 迭代版本 → 设计文档（对应查询 1） ----------
-- 一次查全某型号历次改版下的说明书 / 设计图 / CAD 文件
CREATE VIEW v_product_documents AS
SELECT p.product_id,
       p.model            AS 产品型号,
       p.series           AS 系列,
       pv.version_no      AS 产品版本,
       pv.release_date    AS 版本发布日期,
       d.doc_type         AS 文档类型,
       d.doc_rev          AS 文档修订号,
       d.title            AS 标题,
       d.author           AS 作者,
       d.update_date      AS 更新日期,
       d.file_path        AS 文件路径
FROM product p
JOIN product_version pv ON pv.product_id = p.product_id
JOIN document d         ON d.version_id  = pv.version_id;

-- ---------- 视图 2：统一可供清单（部件层 + 材料层） ----------
-- 部件与材料分表存储，统计时先合并成一张明细视图
CREATE VIEW v_supply_catalog AS
SELECT cs.component_id AS item_id,
       '部件'          AS item_type,
       cs.supplier_id  AS supplier_id,
       cs.supply_price AS supply_price
FROM component_supplier cs
UNION ALL
SELECT ms.material_id, '材料', ms.supplier_id, ms.supply_price
FROM material_supplier ms;

-- ---------- 视图 3：供应商可供能力统计（对应查询 2-A） ----------
-- 平均报价把部件与材料的报价合并计算，仅作演示；
-- 真实业务应分类型统计，见 06_business_queries.sql 的 2-A。
CREATE VIEW v_supplier_capability AS
SELECT s.supplier_id                                        AS 供应商编号,
       s.supplier_name                                      AS 供应商,
       COUNT(DISTINCT CONCAT(c.item_type, c.item_id))        AS 可供物料种类数,
       SUM(CASE WHEN c.item_type = '部件' THEN 1 ELSE 0 END) AS 可供部件数,
       SUM(CASE WHEN c.item_type = '材料' THEN 1 ELSE 0 END) AS 可供材料数,
       ROUND(AVG(c.supply_price), 2)                         AS 平均报价
FROM supplier s
LEFT JOIN v_supply_catalog c ON c.supplier_id = s.supplier_id
GROUP BY s.supplier_id, s.supplier_name;

-- ---------- 视图 4：批次实际供货明细（对应查询 2-C） ----------
-- 与「可供清单」的区别：这里记录的是某批次真实用了谁家的货
CREATE VIEW v_batch_supply_detail AS
SELECT bcs.batch_id,
       CONCAT('C', bcs.component_id) AS item_key,
       '部件'                        AS item_type,
       bcs.component_id              AS item_id,
       bcs.supplier_id               AS supplier_id
FROM batch_component_source bcs
UNION ALL
SELECT bms.batch_id,
       CONCAT('M', bms.material_id),
       '材料',
       bms.material_id,
       bms.supplier_id
FROM batch_material_source bms;

-- ---------- 视图 5：按序列号的完整溯源（对应查询 3-③，本题核心） ----------
-- 链路：serial_no → batch_id → 两层 BOM → batch_*_source → supplier
-- 部件层与材料层用 UNION ALL 合并；自产部件本身不采购成品，
-- 其来源体现在材料层，故显示「（自产件，见材料层）」而非裸 NULL。
CREATE VIEW v_serial_trace AS
SELECT pi.serial_no AS 出厂序列号,
       b.batch_no   AS 批次号,
       p.model      AS 产品型号,
       '部件'       AS 层级,
       c.component_name AS 物料名称,
       COALESCE(s.supplier_name, '（自产件，见材料层）') AS 供应商
FROM product_instance pi
JOIN batch b              ON b.batch_id     = pi.batch_id
JOIN product p            ON p.product_id   = pi.product_id
JOIN product_component pc ON pc.product_id  = pi.product_id
JOIN component c          ON c.component_id = pc.component_id
LEFT JOIN batch_component_source bcs
       ON bcs.batch_id = pi.batch_id AND bcs.component_id = pc.component_id
LEFT JOIN supplier s ON s.supplier_id = bcs.supplier_id
UNION ALL
SELECT pi.serial_no,
       b.batch_no,
       p.model,
       '材料',
       m.material_name,
       COALESCE(sm.supplier_name, '（未登记）')
FROM product_instance pi
JOIN batch b               ON b.batch_id      = pi.batch_id
JOIN product p             ON p.product_id    = pi.product_id
JOIN product_component  pc ON pc.product_id   = pi.product_id
JOIN component_material cm ON cm.component_id = pc.component_id
JOIN material            m ON m.material_id   = cm.material_id
LEFT JOIN batch_material_source bms
       ON bms.batch_id = pi.batch_id AND bms.material_id = cm.material_id
LEFT JOIN supplier sm ON sm.supplier_id = bms.supplier_id;

-- ---------- 验证：列出所有视图 ----------
SHOW FULL TABLES FROM pdm_db WHERE Table_type = 'VIEW';
