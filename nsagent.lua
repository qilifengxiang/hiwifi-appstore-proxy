#!/usr/bin/env lua

-- flock -xn /tmp/ns-agent.lock -c "/usr/bin/lua <agent_path>"

local NS_DEBUG = true

local cjson = require "cjson"
local md5 = require "md5"
local http = require "socket.http"
local inspect = require "inspect"

local API_VERSION = "1.0"
local API_PACKAGE_CONFIG = 'http://willard.com.cn/test.html'
local SD_CARD_DIR = '/tmp/data'
local APK_CACHE_DIR = SD_CARD_DIR .. '/apk_cache'
local IPA_CACHE_DIR = SD_CARD_DIR .. '/ipa_cache'
local TMP_IPA_DIR = SD_CARD_DIR .. '/tmp_ipa'
local TMP_APK_DIR = SD_CARD_DIR .. '/tmp_apk'
local TMP_IPA_NAME = "tmp.ipa"
local TMP_APK_NAME = "tmp.apk"
local DELIMITER = "/"
local PLATFORM_IOS = "ios"
local PLATFORM_ANDROID = "android"

local function debug_log(msg)
    if NS_DEBUG then
        print(msg)
    end
end


function capture(cmd, raw)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s
end


local function calc_md5sum(filename)
    return capture(string.format("md5sum %s | awk '{print $1}'", filename))
end


function is_file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end


local function startswith(str, substr)
    if str == nil or substr == nil then
        return nil, "the string or the sub-stirng parameter is nil"
    end
    if string.find(str, substr) ~= 1 then
        return false
    else
        return true
    end
end


local function get_package_config()
    local response, status_code = http.request(API_PACKAGE_CONFIG)

    if status_code ~= 200 then
        error("Get package config failed.")
    end

    return cjson.decode(response)
end


local function get_cache_dir(platform)
    if platform == PLATFORM_ANDROID then
        return APK_CACHE_DIR
    elseif platform == PLATFORM_IOS then
        return IPA_CACHE_DIR
    else
        error(string.format("Invalid platform: %s", platform))
    end
end


-- 包都匹配返回true, 否则返回false
local function check_all_pkg(packages, platform)
    -- NOTE: 因为是move过去的, 所以认为一定成功, 不再校验md5
    local all_exist = true
    for i=1, #packages do
        local delimiter = ''
        local path = packages[i]["path"]
        if not startswith(path, "/") then
            delimiter = DELIMITER
        end
        path = get_cache_dir(platform) .. delimiter .. path
        if not is_file_exists(path) then
            all_exist = false
        end
    end
    return all_exist
end


local function get_tmp_pkg_name(platform)
    if platform == PLATFORM_ANDROID then
        return TMP_APK_DIR .. DELIMITER .. TMP_APK_NAME
    elseif platform == PLATFORM_IOS then
        return TMP_IPA_DIR .. DELIMITER .. TMP_IPA_NAME
    else
        error(string.format("Invalid platform: %s", platform))
    end
end


local function download_pkg(package, platform)
    local tmp_pkg_name = get_tmp_pkg_name(platform)

    local cmd = "rm -f " .. tmp_pkg_name
    debug_log(cmd)
    os.execute(cmd)

    cmd = string.format("wget '%s' -O %s", package["url"], tmp_pkg_name)
    debug_log(cmd)
    os.execute(cmd)

    local file_md5 = calc_md5sum(tmp_pkg_name)
    if file_md5 ~= package["md5sum"] then
        error(string.format("Invalid MD5: %s md5sum: %s", package["url"], file_md5))
    end
end


local function move_pkg_to_cache_dir(package, platform)
    local delimiter = ''
    local path = string.match(package["path"], "(.+)/[^/]*%.%w+$")
    if path == nil then
        path = "/"
    end
    if not startswith(path, "/") then
        delimiter = DELIMITER
    end

    path = get_cache_dir(platform) .. delimiter .. path

    local cmd = "mkdir -p " .. path
    debug_log(cmd)
    os.execute(cmd)
    cmd = string.format("mv -f %s %s%s", get_tmp_pkg_name(platform), get_cache_dir(platform), package["path"])
    debug_log(cmd)
    os.execute(cmd)
end


local function remove_cache_dir(platform)
    local cmd = string.format("rm -rf %s/*", get_cache_dir(platform))
    debug_log(cmd)
    os.execute(cmd)
end


local function make_all_dir()
    local cmd = "mkdir -p " .. IPA_CACHE_DIR
    debug_log(cmd)
    os.execute(cmd)
    cmd = "mkdir -p " .. TMP_IPA_DIR
    debug_log(cmd)
    os.execute(cmd)
    cmd = "mkdir -p " .. APK_CACHE_DIR
    debug_log(cmd)
    os.execute(cmd)
    cmd = "mkdir -p " .. TMP_APK_DIR
    debug_log(cmd)
    os.execute(cmd)
end


local function update_pkg(package, platform)
    if not check_all_pkg(package, platform) then
        remove_cache_dir(platform)
        make_all_dir()

        for i=1, #package do
            local pkg = package[i]
            download_pkg(pkg, platform)
            move_pkg_to_cache_dir(pkg, platform)
        end
    end

    print(string.format("%s status: %s", platform, tostring(check_all_pkg(package, platform))))
end


local function run()
    make_all_dir()

    local config = get_package_config()
    
    print('=======')

    if config["version"] ~= API_VERSION then
        error("API version does't match")
    end

    -- TODO: check schema

    update_pkg(config["iosPackages"], PLATFORM_IOS)
    update_pkg(config["androidPackages"], PLATFORM_ANDROID)
end


-----------------------------------

run()
