
#!/bin/sh

# 获取 Baihu 服务端口
BAIHU_PORT="${BH_SERVER_PORT:-${PORT:-8052}}"
BAIHU_URL="http://localhost:${BAIHU_PORT}"

# 获取登陆cookie:需要设置用户名和密码
USERNAME="admin"
echo "开始登录 Baihu，端口：${BAIHU_PORT}......"

BHToken=$(
curl -c cookies.txt -s -D - -o /dev/null \
"${BAIHU_URL}/api/v1/auth/login" \
-H 'content-type: application/json' \
--data-raw "{\"username\":\"$USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" \
| awk -F'[=;]' '/Set-Cookie: BHToken=/{print $2}'
)

if [ -z "$BHToken" ]; then
    echo "登录失败，请检查密码和 Baihu 服务状态"
    rm -f cookies.txt
    exit 1
fi

echo "登录成功，开始请求同步"

# 用 Cookie 请求生成同步文件
BACKUP_RESP=$(
    curl -b cookies.txt -X POST \
    "${BAIHU_URL}/api/v1/settings/backup" \
    -H 'content-type: application/json'
)

echo "请求同步完成，等待10秒后开始同步"

# 休眠一段时间等待打包完成
sleep 10

# 获取同步目录下的最新文件
latest_file=$(ls -t /app/data/backups 2>/dev/null | head -n 1)
local_file_path="/app/data/backups/$latest_file"

# ==================== 关键防线：源头校验 ====================

# 1. 检查文件是否存在且大小大于0字节
if [ -z "$latest_file" ] || [ ! -f "$local_file_path" ] || [ ! -s "$local_file_path" ]; then
    echo "❌ 错误：生成的同步文件不存在或大小为0字节！"
    echo "终止上传，保护云端历史同步不被污染。"
    rm -f cookies.txt
    exit 1
fi

# 2. 显示同步文件大小
file_size=$(du -h "$local_file_path" | awk '{print $1}')
echo "📊 同步文件大小：$file_size"

echo "✔️ 校验通过，开始上传到云盘..."

# ==================== 上传云端 ====================

# 将当前同步文件复制到云盘（不删除云端历史同步）
if rclone copy "$local_file_path" "$REMOTE_FOLDER"; then

    echo "☁️ 云端同步上传成功"

    # 清理本次生成的本地临时同步文件
    rm -f "$local_file_path"
    echo "🧹 本地临时同步文件已清理"

    # ==================== 清理云端旧文件 ====================

    echo "🗑️ 正在清理云端10天前的旧同步..."

    if rclone delete "$REMOTE_FOLDER" --min-age 10d; then
        CLEANUP_STATUS=0
        echo "✨ 云端旧同步文件清理完成"
    else
        CLEANUP_STATUS=1
        echo "❌ 警告：云端旧同步文件清理失败"
    fi

else
    echo "❌ 错误：Rclone上传到云盘失败！"

    # 按照原始逻辑，上传失败也删除本地临时同步文件
    rm -f "$local_file_path"
    rm -f cookies.txt
    exit 1
fi

# ==================== 🍒🍒 ====================

echo "========================================"

rm -f cookies.txt

if [ "$CLEANUP_STATUS" -eq 0 ]; then
    echo "🎉 同步：全部完成 ✔️"
else
    echo "🎉 同步：上传成功 ✔️，旧文件清理失败 ❌"
fi

echo "🎉 云端：$REMOTE_FOLDER/$latest_file ✔️"

echo "🎉 Successful! 🎉"

echo "========================================"
