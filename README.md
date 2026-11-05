# PDM 产品数据管理系统（数据库设计）

课程作业 **C1 产品数据管理（PDM）数字化系统** 的数据库模式设计。

## 项目简介

PDM（Product Data Management）用于管理产品相关信息（零件、配置、文档、CAD 文件、结构、权限等）和产品相关过程。本项目实现一个简化的 PDM 数据库，覆盖：

- 产品类型 / 系列 / 型号规格 / 价格
- 产品迭代版本的设计说明书、设计图
- 产品由多个部件构成（BOM）
- 部件来源：采购件 / 自产件
- 自产部件由多种材料构成
- 部件、材料与供应商的多对多供货关系
- 同一批产品共享供货源（批次级锁定）
- 每个产品有唯一出厂序列号

## 数据库表（14 张）

| 表名 | 说明 |
| --- | --- |
| product_type | 产品类型 |
| product | 产品（型号） |
| document | 产品文档（迭代版本） |
| component | 部件 |
| material | 材料 |
| product_component | 产品部件构成（BOM） |
| component_material | 部件材料构成（自产部件） |
| supplier | 供应商 |
| component_supplier | 部件供货 |
| material_supplier | 材料供货 |
| batch | 生产批次 |
| product_instance | 产品实例（出厂序列号） |
| batch_component_source | 批次部件供货源 |
| batch_material_source | 批次材料供货源 |

## 如何运行

1. 安装 MySQL 8.x
2. 打开 MySQL Workbench，新建查询
3. 执行 `schema.sql`
4. 查看最后的查询结果

## 查询示例

- 某个产品的设计文档信息
- 供应商供货情况统计
- 追溯某个产品（序列号）的部件/材料供应商，探究缺陷原因

## ER 图

![ER图](er_diagram.png)