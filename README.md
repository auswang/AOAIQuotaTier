# Azure OpenAI Quota Tier 查询工具

查询 Azure 订阅的 AOAI Quota Tier 及各模型 RPM/TPM 配额信息。

## 功能

- Microsoft 账户登录 Azure
- 选择 Azure 订阅
- 查看当前订阅 Quota Tier（Tier 0-6，含 Free Tier）及升级策略
- Tier 配额参考表：按 Tier 级别展示所有模型的 RPM/TPM 配额
- 实时配额使用：查询各区域的实际 quota 使用情况
- 支持按模型名称、部署类型、区域筛选

## 快速部署

### 配额数据版本

参考表于 **2026-09-30** 根据文末 Microsoft Learn 页面同步，覆盖 Free Tier（Tier 0）和 Tier 1–6，共 538 条记录。
本次更新包含 GPT-6 系列、GPT-6.1-sol、GPT-image-2.5-flare / sunburst，以及 GPT-5.5 配额修正。
`gpt-chat-latest` 按版本区分：2026-05-05、2026-05-28、2026-06-24 使用每 1,000 TPM 对应 10 RPM；2026-08-06 使用每 1,000 TPM 对应 1 RPM。

表中的 `/ 10s` 保留官方的每 10 秒请求窗口；`-` 表示未提供 TPM，不代表无限制。
参考表不是实时配额，已批准的配额增加不会被参考值覆盖。官方正逐步引入订阅级共享配额池，不能将各区域返回的配额简单相加。

现有部署为 `rg-aoai-quota` 中的 `aoai-quota-austin`：
https://aoai-quota-austin.azurewebsites.net 。更新现有站点应部署代码包，不要重新运行创建资源的 `setup.sh`。

本仓库 Azure 运维使用账号 `shenglinwang@hotmail.com`，目标订阅为 **Visual Studio Enterprise**
（`1a90ee96-4f81-4465-9d55-4e10c7197869`）。执行 Azure CLI 命令时应显式指定该订阅，不要依赖本机默认订阅。
正式部署使用仓库已有 GitHub Actions 流程中的 `AZURE_CREDENTIALS` 服务主体凭据；
个人账号与 CI/CD 部署身份不同，不要替换现有凭据。

### 前置条件

- Azure 订阅
- Azure CLI (`az`) 和 `jq`
- （可选）GitHub CLI (`gh`) 用于自动配置 CI/CD

### 一键部署

```bash
chmod +x setup.sh
./setup.sh
```

脚本会自动完成：
1. 创建资源组和 App Service Plan（默认 F1 免费级别）
2. 创建 Web App (Python 3.12)
3. 创建 Azure AD App Registration (SPA 类型)
4. 配置环境变量和启动命令
5. 部署代码
6. （可选）配置 GitHub CI/CD

### 手动部署

```bash
# 创建资源组
az group create --name rg-aoai-quota --location eastasia

# 创建 App Service Plan
az appservice plan create --name plan-aoai-quota --resource-group rg-aoai-quota --sku F1 --is-linux

# 创建 Web App
az webapp create --name <your-app-name> --resource-group rg-aoai-quota --plan plan-aoai-quota --runtime "PYTHON:3.12"

# 配置环境变量
az webapp config appsettings set --name <your-app-name> --resource-group rg-aoai-quota --settings \
    AZURE_CLIENT_ID="<your-client-id>" \
    AZURE_TENANT_ID="common" \
    SCM_DO_BUILD_DURING_DEPLOYMENT="true"

# 配置启动命令
az webapp config set --name <your-app-name> --resource-group rg-aoai-quota \
    --startup-file "gunicorn --bind=0.0.0.0:8000 --timeout 120 app:app"
```

## GitHub CI/CD

推送到 `main` 分支时自动部署。需要在 GitHub 仓库 Settings → Secrets → Actions 中配置：

| Secret | 说明 |
|--------|------|
| `AZURE_CREDENTIALS` | Service Principal 凭据 (JSON) |
| `AZURE_WEBAPP_NAME` | Web App 名称 |
| `AZURE_RESOURCE_GROUP` | 资源组名称 |

## 本地开发

```bash
pip install -r requirements.txt
export AZURE_CLIENT_ID="<your-client-id>"
python app.py
```

访问 http://localhost:8000

## 技术栈

- **后端**: Flask + Gunicorn
- **前端**: MSAL.js v2 + Azure REST API
- **部署**: Azure App Service (Linux)
- **CI/CD**: GitHub Actions

## 参考

- [Azure OpenAI Quotas and Limits](https://learn.microsoft.com/en-us/azure/foundry/openai/quotas-limits?tabs=bash%2Ctier1)
