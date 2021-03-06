local _trace, _warn = util.global_log_factory("plugin/systemctl", "trace", "warn")

assert(os.execute('systemctl --version 2>&1 >/dev/null'), "systemctl not found")
assert(proc.EPROC, "systemctl plugin requires posix proc extra api (eli.proc.extra)")

local _systemctl = {}

function _systemctl.exec(...)
    local _cmd = string.join_strings(" ", ...)
    _trace("Executing systemctl " .. _cmd)
    local _proc = proc.spawn("systemctl", { ... }, {stdio = { stdout = "pipe", stderr = "pipe" }, wait = true })
    if not _proc then
        error("Failed to execute systemctl command: " .. _cmd)
    end
    _trace("systemctl exit code: " .. _proc.exitcode)
    local _stderr = _proc.stderrStream:read("a")
    local _stdout = _proc.stdoutStream:read("a")
    return _proc.exitcode, _stdout, _stderr
end

function _systemctl.install_service(sourceFile, serviceName, options)
    if type(options) ~= "table" then 
        options = {}
    end
    if type(options.kind) ~= "string" then 
       options.kind = "service"
    end
    local _ok, _error = fs.safe_copy_file(sourceFile, "/etc/systemd/system/" .. serviceName .. "." .. options.kind)
    assert(_ok, "Failed to install " .. serviceName .. "." ..options.kind .. " - " .. (_error or ""))

    if type(options.daemonReload) ~= "boolean" or options.daemonReload == true then
        local _exitcode, _stdout, _stderr = _systemctl.exec("daemon-reload")
        if _exitcode ~= 0 then
            _warn({ msg = "Failed to reload systemd daemon!", stdout = _stdout, stderr = _stderr })
        end
    end
    assert(_systemctl.exec("enable", serviceName .. "." .. options.kind) == 0, "Failed to enable service " .. serviceName .. "!")
end

function _systemctl.start_service(serviceName)
    _trace("Starting service: " .. serviceName)
    local _exitcode = _systemctl.exec("start", serviceName)
    assert(_exitcode == 0, "Failed to start service")
    _trace("Service " .. serviceName .. "started...")
end

function _systemctl.stop_service(serviceName)
    _trace("Stoping service: " .. serviceName)
    local _exitcode = _systemctl.exec("stop", serviceName)
    assert(_exitcode == 0, "Failed to stop service")
    _trace("Service " .. serviceName .. "stopped...")
end

function _systemctl.remove_service(serviceName, options)
    if type(options) ~= "table" then 
        options = {}
    end
    if type(options.kind) ~= "string" then
       options.kind = "service"
    end
    _trace("Removing service: " .. serviceName)
    local _exitcode = _systemctl.exec("stop", serviceName)
    assert(_exitcode == 0 or _exitcode == 5, "Failed to stop service")
    _trace("Service " .. serviceName .. "stopped...")
    local _ok, _error = fs.safe_remove("/etc/systemd/system/" .. serviceName .. "." .. options.kind)
    if not _ok then
        error("Failed to remove " .. serviceName .. "." .. options.kind ..  " - " .. (_error or ""))
    end
    
    if type(options.daemonReload) ~= "boolean" or options.daemonReload == true then
        local _exitcode, _stdout, _stderr = _systemctl.exec("daemon-reload")
        if _exitcode ~= 0 then
            _warn({ msg = "Failed to reload systemd daemon!", stdout = _stdout, stderr = _stderr })
        end
    end
    _trace("Service " .. serviceName .. "removed...")
end

function _systemctl.get_service_status(serviceName)
    _trace("Getting service " .. serviceName .. "status...")
    local _exitcode, _stdout = _systemctl.exec("show", "-p", "SubState", "--value", serviceName)
    assert(_exitcode == 0, "Failed to get service status")
    local _status = _stdout:match("%s*(%S*)")
    local _exitcode, _stdout = _systemctl.exec("show", "-p", "ExecMainStartTimestamp", "--value", serviceName)
    assert(_exitcode == 0, "Failed to get service start timestamp")
    local _started = type(_stdout) == "string" and _stdout:gsub("^%s*(.-)%s*$", "%1")
    _trace("Got service " .. serviceName .. " status - " .. (_status or ""))
    return _status, _started
end

return util.generate_safe_functions(_systemctl)
