
#!/bin/sh

# 获取 Baihu 服务端口
BAIHU_PORT="${BH_SERVER_PORT:-${PORT:-8052}}"
BAIHU_URL="http://localhost:${BAIHU_PORT}"

# ===== [修改 1] 自动识别 Rclone 配置格式 =====

if printf '%s' "$RCLONE_CONF" | grep -qE '^[[:space:]]*\['; then
    # 原始配置（支持多行）
    printf '%s\n' "$RCLONE_CONF" > ~/.config/rclone/rclone.conf
    echo "检测到原始 Rclone 配置"
else
    # Base64 单行编码配置
    printf '%s' "$RCLONE_CONF" | base64 -d > ~/.config/rclone/rclone.conf
    echo "检测到 Base64 Rclone 配置"
fi

# ===== [修改 1 结束] =====

# 获取登陆cookie:需要设置用户名和密码
USERNAME="admin"
echo "开始登陆......"
BHToken=$(
curl -c cookies.txt -s -D - -o /dev/null \
"$BAIHU_URL/api/v1/auth/login" \
-H 'content-type: application/json' \
--data-raw "{\"username\":\"$USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" \
| awk -F'[=;]' '/Set-Cookie: BHToken=/{print $2}'
)
echo "登陆成功Token为:$BHToken,开始请求同步"

# 用cookie请求生成同步文件
BACKUP_RESP=$(
    curl -b cookies.txt -X POST "$BAIHU_URL/api/v1/settings/backup" -H 'content-type: application/json' 
)
echo "请求同步完成，等待10秒后开始同步"

# 休眠一段时间等其打包完成
sleep 10

# 获取同步目录下的最新文件
latest_file=$(ls -t /app/data/backups | head -n 1)
local_file_path="/app/data/backups/$latest_file"

# ==================== 【关键防线,源头校验】 ====================
# 1. 检查文件是否存在且大小大于 0 字节
if [ ! -f "$local_file_path" ] || [ ! -s "$local_file_path" ]; then
    echo "❌ 错误: 生成的同步文件不存在或大小为 0 字节！终止上传，保护云端同步文件不被污染。"
    rm -f cookies.txt
    exit 1
fi

# 2. 显示同步文件大小
file_size=$(du -h "$local_file_path" | awk '{print $1}')
echo "📊  同步文件大小: $file_size"

# ==========================================================

echo "✔️  校验通过：同步文件大小和格式正常，开始上传到云盘..."

# 将当前同步文件复制到云盘（注意：没有 rclone delete，确保云端保留历史同步文件）
rclone copy "$local_file_path" "$REMOTE_FOLDER"

if [ $? -eq 0 ]; then
    echo "☁️  云盘同步成功！"
    
    # 清理本次生成的本地临时同步文件，释放磁盘空间
    rm -f "$local_file_path"
    echo "🧹  本地临时同步文件已清理"
    
    # 清理云端 10 天前的旧同步文件（精准按文件的修改时间过滤，不误删近期同步文件）
    echo "🗑️  正在清理云端 10 天前的旧同步文件..."
    rclone delete "$REMOTE_FOLDER" --min-age 10d
    echo "✨  清理已完成"
else
    echo "❌ 错误: rclone 上传到云盘失败！"
    rm -f cookies.txt
    exit 1
fi

rm -f cookies.txt
echo "🎉  同步 🔸  成功 🎉               文件已上传至 : $REMOTE_FOLDER/$latest_file"
echo "🎉  Successful!  🎉"
