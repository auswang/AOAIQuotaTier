#!/bin/bash
set -e

# ========================================
# Azure OpenAI Quota Tier 查询网站 - 一键部署脚本
# ========================================

echo "========================================="
echo "  Azure OpenAI Quota Tier 查询网站部署"
echo "========================================="
echo ""

# Check prerequisites
for cmd in az jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ 需要安装 $cmd。"
        if [ "$cmd" = "az" ]; then
            echo "   安装 Azure CLI: https://learn.microsoft.com/cli/azure/install-azure-cli"
        elif [ "$cmd" = "jq" ]; then
            echo "   macOS: brew install jq"
        fi
        exit 1
    fi
done

# Check Azure login
echo "🔐 检查 Azure 登录状态..."
if ! az account show &> /dev/null; then
    echo "未登录 Azure，正在打开登录页面..."
    az login
fi

CURRENT_ACCOUNT=$(az account show --query '{name:name, id:id}' -o json)
echo "当前账户: $(echo $CURRENT_ACCOUNT | jq -r '.name') ($(echo $CURRENT_ACCOUNT | jq -r '.id'))"
echo ""

# ---- Collect parameters ----
echo "📋 请输入配置信息（回车使用默认值）"
echo "-------------------------------------------"

read -p "资源组名称 [rg-aoai-quota]: " RESOURCE_GROUP
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-aoai-quota}

DEFAULT_WEBAPP="aoai-quota-$(whoami | tr '[:upper:]' '[:lower:]' | head -c 8)"
read -p "Web App 名称（全局唯一）[$DEFAULT_WEBAPP]: " WEBAPP_NAME
WEBAPP_NAME=${WEBAPP_NAME:-$DEFAULT_WEBAPP}

read -p "Azure 区域 [eastasia]: " LOCATION
LOCATION=${LOCATION:-eastasia}

read -p "App Service Plan 名称 [plan-aoai-quota]: " PLAN_NAME
PLAN_NAME=${PLAN_NAME:-plan-aoai-quota}

read -p "App Service SKU (F1=免费, B1=基本) [F1]: " SKU
SKU=${SKU:-F1}

read -p "GitHub 仓库 (格式: owner/repo，留空跳过 CI/CD): " GITHUB_REPO

echo ""
echo "将使用以下配置:"
echo "  资源组:     $RESOURCE_GROUP"
echo "  Web App:    $WEBAPP_NAME"
echo "  区域:       $LOCATION"
echo "  Plan:       $PLAN_NAME (SKU: $SKU)"
echo "  GitHub:     ${GITHUB_REPO:-（跳过）}"
echo ""
read -p "确认继续？(y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    echo "已取消。"
    exit 0
fi

echo ""

# ---- Create Resource Group ----
echo "📁 创建资源组 $RESOURCE_GROUP ..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" -o none
echo "   ✅ 资源组创建成功"

# ---- Create App Service Plan ----
echo "📦 创建 App Service Plan（$SKU 级别, Linux）..."
az appservice plan create \
    --name "$PLAN_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --sku "$SKU" \
    --is-linux \
    -o none
echo "   ✅ App Service Plan 创建成功"

# ---- Create Web App ----
echo "🌐 创建 Web App..."
az webapp create \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --plan "$PLAN_NAME" \
    --runtime "PYTHON:3.12" \
    -o none
echo "   ✅ Web App 创建成功"

WEBAPP_URL="https://${WEBAPP_NAME}.azurewebsites.net"
echo "   🔗 URL: $WEBAPP_URL"

# ---- Create Azure AD App Registration ----
echo "🔑 创建 Azure AD App Registration..."
APP_REG=$(az ad app create \
    --display-name "AOAI Quota Tier Query" \
    --sign-in-audience AzureADandPersonalMicrosoftAccount \
    --web-redirect-uris "$WEBAPP_URL" \
    --enable-id-token-issuance true \
    --query '{appId:appId, id:id}' \
    -o json)

APP_CLIENT_ID=$(echo $APP_REG | jq -r '.appId')
APP_OBJECT_ID=$(echo $APP_REG | jq -r '.id')
echo "   ✅ App Registration 创建成功"
echo "   Client ID: $APP_CLIENT_ID"

# Configure SPA redirect URI
echo "   配置 SPA 重定向 URI..."
az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/$APP_OBJECT_ID" \
    --headers 'Content-Type=application/json' \
    --body "{\"spa\":{\"redirectUris\":[\"$WEBAPP_URL\",\"http://localhost:8000\"]}}" \
    -o none 2>/dev/null || true
echo "   ✅ SPA 重定向 URI 已配置"

# ---- Configure Web App ----
echo "⚙️  配置 Web App 环境变量..."
az webapp config appsettings set \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
        AZURE_CLIENT_ID="$APP_CLIENT_ID" \
        AZURE_TENANT_ID="common" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true" \
    -o none

az webapp config set \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --startup-file "gunicorn --bind=0.0.0.0:8000 --timeout 120 app:app" \
    -o none
echo "   ✅ Web App 配置完成"

# ---- Deploy code ----
echo "📤 部署代码到 Web App..."
cd "$(dirname "$0")"
zip -r /tmp/aoai-quota-deploy.zip . \
    -x '.git/*' '.github/*' '__pycache__/*' '*.pyc' 'venv/*' '.env' '.DS_Store' 'setup.sh'

az webapp deploy \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --src-path /tmp/aoai-quota-deploy.zip \
    --type zip \
    -o none 2>/dev/null || \
az webapp deployment source config-zip \
    --name "$WEBAPP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --src /tmp/aoai-quota-deploy.zip \
    -o none

rm -f /tmp/aoai-quota-deploy.zip
echo "   ✅ 代码部署成功"

# ---- Configure GitHub CI/CD ----
if [ -n "$GITHUB_REPO" ]; then
    echo "🔄 配置 GitHub CI/CD..."

    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    echo "   创建 Service Principal..."
    SP_CREDS=$(az ad sp create-for-rbac \
        --name "sp-aoai-quota-deploy" \
        --role contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --sdk-auth 2>/dev/null || az ad sp create-for-rbac \
        --name "sp-aoai-quota-deploy" \
        --role contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --json-auth)

    if command -v gh &> /dev/null; then
        echo "$SP_CREDS" | gh secret set AZURE_CREDENTIALS --repo "$GITHUB_REPO"
        echo "$WEBAPP_NAME" | gh secret set AZURE_WEBAPP_NAME --repo "$GITHUB_REPO"
        echo "$RESOURCE_GROUP" | gh secret set AZURE_RESOURCE_GROUP --repo "$GITHUB_REPO"
        echo "   ✅ GitHub Secrets 已自动配置"
    else
        echo ""
        echo "   ⚠️  未安装 gh CLI，请手动在 GitHub 仓库 Settings → Secrets → Actions 中添加："
        echo "   ──────────────────────────────────────────"
        echo "   AZURE_CREDENTIALS:"
        echo "$SP_CREDS"
        echo ""
        echo "   AZURE_WEBAPP_NAME: $WEBAPP_NAME"
        echo "   AZURE_RESOURCE_GROUP: $RESOURCE_GROUP"
        echo "   ──────────────────────────────────────────"
    fi
fi

# ---- Done ----
echo ""
echo "========================================="
echo "  🎉 部署完成！"
echo "========================================="
echo ""
echo "  Web App URL:  $WEBAPP_URL"
echo "  Client ID:    $APP_CLIENT_ID"
echo ""
echo "  下一步："
if [ -n "$GITHUB_REPO" ]; then
    echo "  1. git add -A && git commit -m 'initial deploy' && git push"
    echo "  2. 后续代码更新会通过 GitHub Actions 自动部署"
else
    echo "  1. 在 GitHub 创建仓库，上传代码"
    echo "  2. 重新运行此脚本并输入 GitHub 仓库地址来配置 CI/CD"
fi
echo ""
