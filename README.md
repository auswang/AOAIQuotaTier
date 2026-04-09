# Azure OpenAI Quota Tier 查询工具

一个轻量级 Web 应用，用来查询 Azure 订阅的 AOAI Quota Tier 及各模型配额信息。

## 功能

- 🔐 使用 Microsoft 账户登录 Azure
- 📋 选择 Azure 订阅
- 🏷️ 查看当前订阅的 Quota Tier（Tier 1-6）
- 📊 以表格形式展示所有 AOAI 模型的 Quota 配额
- 🔍 支持按模型名称和部署类型筛选

## 部署

### 前置条件

1. Azure 订阅
2. 已在 Azure AD 中注册应用（App Registration），获取 Client ID
3. GitHub 仓库

### Azure App Registration 设置

1. 在 Azure Portal → Microsoft Entra ID → App registrations 中创建新应用
2. 设置 Redirect URI 为 `https://<your-app>.azurewebsites.net`（类型选 SPA）
3. 在 API permissions 中添加：`https://management.azure.com/user_impersonation`（Delegated）
4. 记录 Application (client) ID

### Azure Web App 创建

```bash
# 创建资源组
az group create --name rg-aoai-quota --location eastasia

# 创建 App Service Plan (F1 免费)
az appservice plan create --name plan-aoai-quota --resource-group rg-aoai-quota --sku F1 --is-linux

# 创建 Web App
az webapp create --name <your-app-name> --resource-group rg-aoai-quota --plan plan-aoai-quota --runtime "PYTHON:3.12"

# 配置环境变量
az webapp config appsettings set --name <your-app-name> --resource-group rg-aoai-quota --settings \
    AZURE_CLIENT_ID="<your-client-id>" \
    AZURE_TENANT_ID="common" \
    SCM_DO_BUILD_DURING_DEPLOYMENT="true"

# 配置启动命令
az webapp config set --name <your-app-name> --resource-group rg-aoai-quota --startup-file "gunicorn --bind=0.0.0.0:8000 --timeout 120 app:app"
```

### GitHub Actions 部署

1. 在 Azure Portal 中下载 Web App 的 Publish Profile
2. 在 GitHub 仓库 Settings → Secrets → Actions 中添加：
   - `AZURE_WEBAPP_NAME`: 你的 Web App 名称
   - `AZURE_WEBAPP_PUBLISH_PROFILE`: Publish Profile 的完整 XML 内容
3. Push 代码到 `main` 分支即自动部署

## 本地运行

```bash
pip install -r requirements.txt
export AZURE_CLIENT_ID="your-client-id"
export AZURE_TENANT_ID="common"
python app.py
```

访问 http://localhost:8000

## 技术栈

- **后端**: Flask + Gunicorn
- **前端**: 原生 HTML/CSS/JS + MSAL.js v2
- **认证**: MSAL.js (OAuth 2.0 PKCE)
- **API**: Azure Management REST API
- **部署**: Azure App Service (F1 Free) + GitHub Actions CI/CD
