# 文档构建

文档入口为 `docs/index.rst`，Markdown 由 MyST 解析。源文件中的私人示例必须使用占位符。

在仓库根目录使用 Python 3.12 虚拟环境：

```sh
python -m venv .local/docs-venv
. .local/docs-venv/bin/activate
python -m pip install -r docs/requirements.txt
python -m sphinx -W --keep-going -b html docs .local/docs-html
```

Windows 使用 `.local/docs-venv/Scripts/Activate.ps1` 激活。输出入口为 `.local/docs-html/index.html`。`.local/` 不提交。

GitHub Pages 现有工作流在 `docs` 分支更新时发布；亚瑟固件发布包会携带对应操作手册和 profile 标识。更新文档源文件不会自动在 main 分支发布 Pages。

[在线文档](https://eze-root.github.io/JDC-Arthur/) 可能落后于当前工作区，应以此次固件随附的说明与构建信息为准。
