#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验 schema.sql 里的示例数据是否自洽（不需要安装 MySQL）。

用法：
    python tests/validate_seed_data.py

检查内容：
    1. 各表主键是否重复
    2. 普通外键引用的父行是否存在
    3. batch_*_source 的复合外键 (物料, 供应商) 是否在可供清单里登记过
    4. 单品的 product_id 是否与所属批次的 product_id 一致
    5. 每个批次的 BOM（采购部件 + 自产件材料）是否都有实际供货源
       -> 保证 6 个序列号做溯源查询时不会出现 NULL 供应商
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

SQL_PATH = Path(__file__).resolve().parent.parent / "schema.sql"

# 每张表主键所在列（0 起）
PK_COLS = {
    "product_type": [0], "product": [0], "product_version": [0], "document": [0],
    "component": [0], "material": [0], "product_component": [0, 1],
    "component_material": [0, 1], "supplier": [0],
    "component_supplier": [0, 1], "material_supplier": [0, 1],
    "batch": [0], "product_instance": [0],
    "batch_component_source": [0, 1], "batch_material_source": [0, 1],
    "sys_role": [0], "sys_user": [0], "doc_permission": [0, 1],
}


def split_values(text):
    """按逗号切分一个元组，忽略单引号内的逗号；同时去掉字符串两侧引号。"""
    out, cur, in_str = [], "", False
    i = 0
    while i < len(text):
        c = text[i]
        if c == "'":
            if in_str and i + 1 < len(text) and text[i + 1] == "'":
                cur += "'"
                i += 2
                continue
            in_str = not in_str
            i += 1
            continue
        if c == "," and not in_str:
            out.append(cur.strip())
            cur = ""
            i += 1
            continue
        cur += c
        i += 1
    out.append(cur.strip())
    return out


def parse_inserts(sql_text):
    """抓出所有 INSERT INTO ... VALUES ...; 块，返回 {表名: [行, ...]}。"""
    lines = sql_text.splitlines()
    data = defaultdict(list)
    i = 0
    while i < len(lines):
        m = re.match(r"\s*INSERT\s+INTO\s+(\w+)\s+VALUES", lines[i], re.I)
        if m:
            table = m.group(1).lower()
            body = lines[i][m.end():]
            while ";" not in body and i + 1 < len(lines):
                i += 1
                body += "\n" + lines[i]
            body = body.split(";", 1)[0]
            for tup in re.findall(r"\(([^()]*)\)", body):
                row = split_values(tup)
                if row and row[0] != "":
                    data[table].append(row)
        i += 1
    return data


def main():
    if not SQL_PATH.exists():
        print("[FAIL] 找不到 schema.sql:", SQL_PATH)
        return 1

    sql_text = SQL_PATH.read_text(encoding="utf-8")
    d = parse_inserts(sql_text)
    errors = []

    if not d:
        print("[FAIL] 没有解析到任何 INSERT 语句")
        return 1

    # 1. 主键唯一性
    total_rows = 0
    for table, cols in PK_COLS.items():
        rows = d.get(table, [])
        total_rows += len(rows)
        seen = set()
        for row in rows:
            key = tuple(row[c] for c in cols)
            if key in seen:
                errors.append(f"主键重复: {table} {key}")
            seen.add(key)
    print(f"[OK] 主键检查: {len(PK_COLS)} 张表 / {total_rows} 行")

    def ids(table, col=0):
        return {r[col] for r in d.get(table, [])}

    type_ids = ids("product_type")
    product_ids = ids("product")
    version_ids = ids("product_version")
    component_ids = ids("component")
    material_ids = ids("material")
    supplier_ids = ids("supplier")
    batch_ids = ids("batch")
    role_ids = ids("sys_role")

    # 2. 普通外键
    fk_checks = [
        ("product", 1, type_ids, "product_type"),
        ("product_version", 1, product_ids, "product"),
        ("document", 1, version_ids, "product_version"),
        ("product_component", 0, product_ids, "product"),
        ("product_component", 1, component_ids, "component"),
        ("component_material", 0, component_ids, "component"),
        ("component_material", 1, material_ids, "material"),
        ("component_supplier", 0, component_ids, "component"),
        ("component_supplier", 1, supplier_ids, "supplier"),
        ("material_supplier", 0, material_ids, "material"),
        ("material_supplier", 1, supplier_ids, "supplier"),
        ("batch", 2, product_ids, "product"),
        ("product_instance", 1, product_ids, "product"),
        ("product_instance", 2, batch_ids, "batch"),
        ("sys_user", 2, role_ids, "sys_role"),
        ("doc_permission", 0, role_ids, "sys_role"),
    ]
    n_fk = 0
    for table, col, parent, name in fk_checks:
        for row in d.get(table, []):
            n_fk += 1
            if row[col] not in parent:
                errors.append(f"外键缺失: {table}.{row[col]} 在 {name} 中不存在")
    print(f"[OK] 外键检查: {n_fk} 处引用")

    # 3. 复合外键：批次供货源必须来自可供清单
    comp_sup = {(r[0], r[1]) for r in d.get("component_supplier", [])}
    mat_sup = {(r[0], r[1]) for r in d.get("material_supplier", [])}
    comp_src = {(r[0], r[1]): r[2] for r in d.get("batch_component_source", [])}
    mat_src = {(r[0], r[1]): r[2] for r in d.get("batch_material_source", [])}

    for (b, c), s in comp_src.items():
        if b not in batch_ids:
            errors.append(f"复合外键: batch_component_source 批次 {b} 不存在")
        if c not in component_ids:
            errors.append(f"复合外键: batch_component_source 部件 {c} 不存在")
        if (c, s) not in comp_sup:
            errors.append(f"复合外键: 部件 {c} 未登记由供应商 {s} 供货")
    for (b, m), s in mat_src.items():
        if b not in batch_ids:
            errors.append(f"复合外键: batch_material_source 批次 {b} 不存在")
        if m not in material_ids:
            errors.append(f"复合外键: batch_material_source 材料 {m} 不存在")
        if (m, s) not in mat_sup:
            errors.append(f"复合外键: 材料 {m} 未登记由供应商 {s} 供货")
    print(f"[OK] 复合外键: {len(comp_src)} 条部件供货源 + {len(mat_src)} 条材料供货源")

    # 4. 单品与批次的型号一致
    batch_product = {r[0]: r[2] for r in d.get("batch", [])}
    for row in d.get("product_instance", []):
        sn, p, b = row[0], row[1], row[2]
        if batch_product.get(b) != p:
            errors.append(f"批次不一致: {sn} 的型号 {p} 与批次 {b} 的型号 {batch_product.get(b)} 不符")
    print(f"[OK] 批次一致性: {len(d.get('product_instance', []))} 个出厂序列号")

    # 5. 溯源完整性：每个批次的 BOM 都要能查到实际供应商
    source_type = {r[0]: r[3] for r in d.get("component", [])}
    bom = defaultdict(set)
    for r in d.get("product_component", []):
        bom[r[0]].add(r[1])
    mats = defaultdict(set)
    for r in d.get("component_material", []):
        mats[r[0]].add(r[1])

    covered = 0
    for b, p in batch_product.items():
        for c in bom.get(p, set()):
            if source_type.get(c) == "采购" and (b, c) not in comp_src:
                errors.append(f"溯源缺口: 批次 {b} 的采购部件 {c} 没有供货源")
            else:
                covered += 1
            for m in mats.get(c, set()):
                if (b, m) not in mat_src:
                    errors.append(f"溯源缺口: 批次 {b} 的材料 {m} 没有供货源")
                else:
                    covered += 1
    print(f"[OK] 溯源完整性: {len(batch_product)} 个批次 / {covered} 项物料均有实际供货源")

    # 业务提示（不算错误）
    self_made_in_supplier = sorted(
        {r[0] for r in d.get("component_supplier", []) if source_type.get(r[0]) == "自产"}
    )
    if self_made_in_supplier:
        print(f"[WARN] 自产部件出现在采购可供清单中: {self_made_in_supplier}")

    if errors:
        print(f"\n[FAIL] 共 {len(errors)} 个问题:")
        for e in errors[:30]:
            print("  -", e)
        return 1

    print("\n[PASS] 示例数据自洽，可以导入 MySQL。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
