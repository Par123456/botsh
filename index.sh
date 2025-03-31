#!/bin/bash

declare -A CONFIG
CONFIG=(
    [API_BASE]="https://i.instagram.com/api/v1"
    [WEB_BASE]="https://www.instagram.com"
    [USER_AGENT]="Instagram 76.0.0.15.395 Android (24/7.0; 640dpi; 1440x2560; samsung; SM-G935F; hero2lte; samsungexynos8890; en_US; 138226743)"
    [DEVICE_SETTINGS]='{
        "app_version":"76.0.0.15.395",
        "android_version":24,
        "android_release":"7.0",
        "dpi":"640dpi",
        "resolution":"1440x2560",
        "manufacturer":"samsung",
        "device":"SM-G935F",
        "model":"hero2lte",
        "cpu":"samsungexynos8890",
        "version_code":"138226743"
    }'
    [SESSION_FILE]=".instagram_session"
    [COOKIE_FILE]=".instagram_cookies"
    [LOG_FILE]="instagram_bot.log"
    [ERROR_LOG]="error.log"
    [DELAY_MIN]=2
    [DELAY_MAX]=5
    [RETRY_ATTEMPTS]=3
    [RETRY_DELAY]=5
)

declare -a SUCCESS_MESSAGES=(
    "✨ Dear valued follower, thank you for your amazing support! Here's a special message just for you. 🌟"
    "🎉 We're so grateful to have you in our community! Your engagement means the world to us. 💫"
    "💖 Thank you for being an incredible part of our journey! Your support inspires us every day. ✨"
    "🌟 You're amazing! Thanks for being such a wonderful supporter of our content. 💝"
    "💫 We appreciate you more than words can express! Thank you for your continued support. 🎊"
)

declare -a FOLLOW_REQUEST_MESSAGES=(
    "Please follow us to participate in this special engagement! 🌟"
    "Want to join the fun? Make sure to follow us first! ✨"
    "Follow us to unlock special content and interactions! 💫"
)

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "${CONFIG[LOG_FILE]}"
    
    if [[ "$level" == "ERROR" ]]; then
        echo "[$timestamp] [$level] $message" >> "${CONFIG[ERROR_LOG]}"
    fi
    
    if [[ "$level" != "DEBUG" ]]; then
        echo "[$level] $message"
    fi
}

generate_uuid() {
    python3 -c "import uuid; print(str(uuid.uuid4()))"
}

generate_device_id() {
    echo "android-$(openssl rand -hex 16)"
}

random_delay() {
    local min="${CONFIG[DELAY_MIN]}"
    local max="${CONFIG[DELAY_MAX]}"
    local delay=$((RANDOM % (max - min + 1) + min))
    sleep "$delay"
}

encrypt_password() {
    local password="$1"
    local key="$(openssl rand -hex 32)"
    local iv="$(openssl rand -hex 16)"
    
    local encrypted=$(echo -n "$password" | openssl enc -aes-256-cbc -K "$key" -iv "$iv" -base64)
    echo "${key}:${iv}:${encrypted}"
}

decrypt_password() {
    local encrypted_data="$1"
    IFS=':' read -r key iv encrypted <<< "$encrypted_data"
    
    echo -n "$encrypted" | openssl enc -aes-256-cbc -d -K "$key" -iv "$iv" -base64
}

create_session() {
    local username="$1"
    local password="$2"
    local device_id=$(generate_device_id)
    local uuid=$(generate_uuid)
    
    
    local init_response=$(curl -s -c "${CONFIG[COOKIE_FILE]}" \
        -H "User-Agent: ${CONFIG[USER_AGENT]}" \
        "${CONFIG[WEB_BASE]}")
    
    local csrf_token=$(grep -o "csrftoken=.*" "${CONFIG[COOKIE_FILE]}" | cut -d= -f2)
    
    
    local login_data="{
        \"username\":\"$username\",
        \"password\":\"$password\",
        \"device_id\":\"$device_id\",
        \"uuid\":\"$uuid\",
        \"login_attempt_count\":0
    }"
    
    
    local login_response=$(curl -s -X POST \
        -H "User-Agent: ${CONFIG[USER_AGENT]}" \
        -H "X-CSRFToken: $csrf_token" \
        -H "Content-Type: application/json" \
        -b "${CONFIG[COOKIE_FILE]}" \
        -c "${CONFIG[COOKIE_FILE]}" \
        "${CONFIG[API_BASE]}/accounts/login/" \
        --data "$login_data")
    
    
    if echo "$login_response" | grep -q "\"status\":\"ok\""; then
        log "INFO" "Login successful for user: $username"
        save_session_data "$username" "$device_id" "$uuid" "$csrf_token"
        return 0
    elif echo "$login_response" | grep -q "checkpoint_required"; then
        handle_2fa "$username" "$csrf_token" "$device_id" "$uuid"
        return $?
    else
        log "ERROR" "Login failed: $(echo "$login_response" | jq -r '.message')"
        return 1
    fi
}

handle_2fa() {
    local username="$1"
    local csrf_token="$2"
    local device_id="$3"
    local uuid="$4"
    
    log "INFO" "2FA verification required for user: $username"
    echo "Two-factor authentication required."
    echo "Select verification method:"
    echo "1. SMS"
    echo "2. Email"
    read -r method_choice
    
    local verification_method
    case $method_choice in
        1) verification_method="phone";;
        2) verification_method="email";;
        *) log "ERROR" "Invalid verification method choice"; return 1;;
    esac
    
    
    local request_code_response=$(curl -s -X POST \
        -H "User-Agent: ${CONFIG[USER_AGENT]}" \
        -H "X-CSRFToken: $csrf_token" \
        -b "${CONFIG[COOKIE_FILE]}" \
        "${CONFIG[API_BASE]}/accounts/send_two_factor_login_sms/" \
        --data "{\"verification_method\":\"$verification_method\"}")
    
    echo "Please enter the verification code:"
    read -r verification_code
    
    
    local verify_response=$(curl -s -X POST \
        -H "User-Agent: ${CONFIG[USER_AGENT]}" \
        -H "X-CSRFToken: $csrf_token" \
        -b "${CONFIG[COOKIE_FILE]}" \
        "${CONFIG[API_BASE]}/accounts/two_factor_login/" \
        --data "{
            \"verification_code\":\"$verification_code\",
            \"two_factor_identifier\":\"$(echo "$request_code_response" | jq -r '.two_factor_identifier')\",
            \"username\":\"$username\",
            \"device_id\":\"$device_id\",
            \"uuid\":\"$uuid\"
        }")
    
    if echo "$verify_response" | grep -q "\"status\":\"ok\""; then
        log "INFO" "2FA verification successful"
        save_session_data "$username" "$device_id" "$uuid" "$csrf_token"
        return 0
    else
        log "ERROR" "2FA verification failed"
        return 1
    fi
}

save_session_data() {
    local username="$1"
    local device_id="$2"
    local uuid="$3"
    local csrf_token="$4"
    
    cat > "${CONFIG[SESSION_FILE]}" << EOF
USERNAME=$username
DEVICE_ID=$device_id
UUID=$uuid
CSRF_TOKEN=$csrf_token
TIMESTAMP=$(date +%s)
EOF
}


get_media_info() {
    local media_url="$1"
    local media_id
    
    if [[ "$media_url" =~ /p/([^/]+) ]]; then
        media_id="${BASH_REMATCH[1]}"
    elif [[ "$media_url" =~ /reel/([^/]+) ]]; then
        media_id="${BASH_REMATCH[1]}"
    elif [[ "$media_url" =~ /stories/([^/]+) ]]; then
        media_id="${BASH_REMATCH[1]}"
    else
        log "ERROR" "Invalid media URL format"
        return 1
    fi
    
    local media_info=$(curl -s \
        -H "User-Agent: ${CONFIG[USER_AGENT]}" \
        -b "${CONFIG[COOKIE_FILE]}" \
        "${CONFIG[API_BASE]}/media/$media_id/info/")
    
    echo "$media_info"
}


monitor_comments() {
    local media_id="$1"
    local target_comment="$2"
    
    log "INFO" "Starting comment monitoring for media ID: $media_id"
    
    while true; do
        local comments_response=$(curl -s \
            -H "User-Agent: ${CONFIG[USER_AGENT]}" \
            -b "${CONFIG[COOKIE_FILE]}" \
            "${CONFIG[API_BASE]}/media/$media_id/comments/")
        
        process_comments "$comments_response" "$target_comment" "$media_id"
        
        random_delay
        
        
        if [[ -f "control.txt" ]]; then
            local command=$(cat control.txt)
            case "$command" in
                "end")
                    log "INFO" "Received end command. Stopping bot."
                    cleanup_and_exit
                    ;;
                "change")
                    log "INFO" "Received change command. Restarting bot."
                    rm control.txt
                    main
                    ;;
            esac
        fi
    done
}

process_comments() {
    local comments_data="$1"
    local target_comment="$2"
    local media_id="$3"
    
    echo "$comments_data" | jq -r '.comments[]' | while read -r comment; do
        local comment_text=$(echo "$comment" | jq -r '.text')
        local commenter_id=$(echo "$comment" | jq -r '.user.pk')
        local commenter_username=$(echo "$comment" | jq -r '.user.username')
        
        if [[ "$comment_text" == "$target_comment" ]]; then
            handle_matching_comment "$commenter_id" "$commenter_username" "$media_id"
        fi
    done
}

handle_matching_comment() {
    local user_id="$1"
    local username="$2"
    local media_id="$3"
    
    if check_follow_status "$user_id"; then
        
        local random_index=$((RANDOM % ${#SUCCESS_MESSAGES[@]}))
        local message="${SUCCESS_MESSAGES[$random_index]}"
        
        send_direct_message "$user_id" "$message"
        post_comment_reply "$media_id" "@$username Thank you for participating! 🎉"
    else
        
        local random_index=$((RANDOM % ${#FOLLOW_REQUEST_MESSAGES[@]}))
        local message="${FOLLOW_REQUEST_MESSAGES[$random_index]}"
        
        post_comment_reply "$media_id" "@$username $message"
    fi
}


main() {
    log "INFO" "Starting Instagram Bot"
    
    
    if [[ -f "${CONFIG[SESSION_FILE]}" ]]; then
        source "${CONFIG[SESSION_FILE]}"
        log "INFO" "Loaded existing session for user: $USERNAME"
    else
        echo "Enter Instagram username:"
        read -r username
        echo "Enter Instagram password:"
        read -rs password
        echo
        
        if ! create_session "$username" "$password"; then
            log "ERROR" "Failed to create session"
            return 1
        fi
    fi
    
    
    echo "Enter media link (post/story/reel):"
    read -r media_link
    
    local media_info=$(get_media_info "$media_link")
    if [[ $? -ne 0 ]]; then
        log "ERROR" "Failed to get media information"
        return 1
    fi
    
    
    echo "Enter target comment:"
    read -r target_comment
    
    
    monitor_comments "$(echo "$media_info" | jq -r '.id')" "$target_comment"
}

cleanup_and_exit() {
    log "INFO" "Cleaning up and exiting"
    rm -f "${CONFIG[SESSION_FILE]}" "${CONFIG[COOKIE_FILE]}"
    exit 0
}


trap cleanup_and_exit SIGINT SIGTERM


main