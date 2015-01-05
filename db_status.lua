-- vim: ts=4 sw=4 expandtab ai syntax=lua
--
-- Lua Script to connect to MySQL and PostgreSQL databases and fetch status
--

function rows (connection, sql_statement)
    -- retrieve a cursor
    local cursor = assert (connection:execute (sql_statement))
    local row = {}
    local isclosed = false
    return function ()
        -- get all rows, the rows will be numerically indexed
        row = cursor:fetch(row, "n")
        if row == nil then
            cursor:close()
            isclosed = true
            return nil
        end
        -- for key,value in pairs(cursor:getcoltypes()) do print(key,value) end
        return unpack(row)
    end
end

function db_status(env, conn_params, query_string)
    local result = {}
    -- connect to data source
    local con = assert (env:connect(unpack(conn_params)))

    local rownr = 0
    for name, last_import, avg_exec_time, num_items, status in rows (con, query_string) do
        if last_import == nil then
            last_import = "NULL"
        end
        if avg_exec_time == nil then
            avg_exec_time = 0
        end
        if num_items == nil then
            num_items = 0
        end
        if status == nil then
            status = "NULL"
        end
        result[rownr] = {
            ["name"] = name,
            ["last_import"]  = last_import,
            ["avg_exec_time"] = math.floor(avg_exec_time/1000+0.5),
            ["num_items"] = num_items,
            ["status"] = status
        }
        rownr = rownr + 1
    end

    con:close()
    return result
end

function mysql_status(conn_params, query_string)
    -- create environment object
    local env = assert (luasql.mysql())
    local result = db_status(env, conn_params, query_string)
    env:close()
    return result
end

function postgres_status(conn_params, query_string)
    -- create environment object
    local env = assert (luasql.postgres())
    local result = db_status(env, conn_params, query_string)
    env:close()
    return result
end

-- load driver
require "luasql.mysql"
require "luasql.postgres"

--
--         Status functions
-- 
-- Status functions returns result in the form:
-- (name, last_run, avg_run_time, num_items, status)
--

--
-- IDD Heartbeat DB status
--
function get_idd_heartbeat_status(conn_params)

    local query_string = "SELECT \
        server, \
        '' as last_import, \
        0 as avg_exec_time, \
        (SELECT \
            COUNT(*) AS count \
        FROM heartbeat_tock \
        WHERE server=s.server \
            AND response_code = 200 \
            AND downloader_seen IS NULL \
            AND creation_time < date_add(NOW(), INTERVAL -15 MINUTE)) AS num_items, \
        '' as status \
    FROM \
        (SELECT 'google' AS server UNION SELECT 'google-staging' AS server) AS s\
    ;"

    return mysql_status(conn_params, query_string)
end

--
-- DIIS production DB status
--
function get_diis_cruncher_status(conn_params)

    local query_string = "SELECT \
        cruncher.name, \
        UNIX_TIMESTAMP(NOW()) - last_import AS last_import, \
        aet*30 AS avg_exec_time, \
        0 AS num_items, \
        cruncher_status.name AS status \
    FROM cruncher \
        INNER JOIN cruncher_status ON (cruncher.status=cruncher_status.id) \
    WHERE cruncher.id = 526 \
    ;"

    return mysql_status(conn_params, query_string)
end

--
-- Generic crashtool DB status
--
function get_crashtool_status(conn_params, plugin_names)
    local query_string = "SELECT \
        name, \
        (SELECT \
        ROUND(EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))) \
        FROM crashes \
        WHERE plugin_id = plugins.id) AS max_created_at, \
        0 as avg_exec_time, \
        0 as num_items, \
        '' as status \
    FROM plugins \
    WHERE name IN ('" .. implode("', '", plugin_names) .. "');"

    return postgres_status(conn_params, query_string)
end

--
-- Crashtool production DB status
--
function get_crashtool_prod_status(conn_params)
    local plugin_names = {"idd_import", "mtbf_import"}
    return get_crashtool_status(conn_params, plugin_names)
end

--
-- Crashtool stage DB status
--
function get_crashtool_stage_status(conn_params)
    local plugin_names = {"idd_import", "mtbf_import"}
    return get_crashtool_status(conn_params, plugin_names)
end

--
-- Crashtool RCA DB status
--
function get_crashtool_rca_status(conn_params)
    local plugin_names = {"rca_importer" }
    return get_crashtool_status(conn_params, plugin_names)
end


--
-- Utility functions
--
function table_as_string(table)
    local result = "{ "
    for k, v in pairs(table) do result = result .. ", " .. k .. " : " .. v end
    return result .. " }"
end

function seconds_to_hms(seconds)
    local hours = math.floor(seconds/3600)
    local minutes = math.floor((seconds % 3600)/60)
    local seconds = (seconds % 3600) % 60
    return hours .. "h:" .. minutes .. "m:" .. seconds .."s"
end

--
-- Crashtool utility functions
--

--
-- Split and join a table to a string
--
function implode(delimiter, list)
  local len = #list
  if len == 0 then
    return ""
  end
  local string = list[1]
  for i = 2, len do
    string = string .. delimiter .. list[i]
  end
  return string
end




-- 
-- UI Functions
-- 

--
-- Fonts required:
-- Entypo - http://dl.dropboxusercontent.com/u/4339492/Entypo.zip (http://www.entypo.com/)
--

local hb_prototype_status = { ["name"] = "google-staging", ["last_import"] = 0, ["avg_exec_time"] = 0, ["num_items"] = 0, ["status"] = "unknown" }
local hb_live_status = { ["name"] = "google", ["last_import"] = 0, ["avg_exec_time"] = 0, ["num_items"] = 0, ["status"] = "unknown" }
local diis_cruncher_status = { ["name"] = "DIIS production DB", ["last_import"] = 0, ["avg_exec_time"] = 0, ["num_items"] = 0, ["status"] = "unknown" }
local crashtool_prod_idd_status = { ["name"] = "idd_import", ["last_import"] = 0, ["avg_exec_time"] = 0, ["num_items"] = 0, ["status"] = "unknown" }
local crashtool_prod_mtbf_status = { ["name"] = "mtbf_import", ["last_import"] = 0, ["avg_exec_time"] = 0, ["num_items"] = 0, ["status"] = "unknown" }
local crashtool_rca_status = { ["name"] = "rca_importer", ["last_import"] = 0, ["avg_exec_time"] = 0, ["num_items"] = 0, ["status"] = "unknown" }

function db_update(settings)
    local hb_status = get_idd_heartbeat_status(settings.idd_heartbeat)
    hb_prototype_status = hb_status[1]
    hb_live_status = hb_status[0]
    -- hack to make text alignment in UI nicer - dependent on font and length of name..
    hb_live_status.name = string.format("%-21s", hb_live_status.name)

    diis_cruncher_status = get_diis_cruncher_status(settings.idd_cruncherenv)[0]
    local crashtool_prod_status = get_crashtool_prod_status(settings.crashtool_prod)
    crashtool_prod_idd_status = crashtool_prod_status[1]
    crashtool_prod_mtbf_status = crashtool_prod_status[0]

    -- crashtool_stage_status = get_crashtool_stage_status()[0]
    -- crashtool_rca_status = get_crashtool_rca_status(settings.crashtool_rca)[0]
end

function db_heartbeat_status(hb_status)
    local hb_missing = tonumber(hb_status["num_items"])
    local color = "888888" -- grey color (unknown)
    if hb_missing > 151 then
        color = "cc0000" -- red color
    elseif hb_missing > 0 then
        color = "cccc00" -- yellow color
    elseif hb_missing == 0 then
        color = "00cc00" -- green color
    end
    return "${color #" .. color .. "}${font Entypo:size=24}▶${color #888888}${font}${voffset -4}" .. string.format(" HB: %-15s", hb_status["name"]) ..  "${offset  40}" .. hb_status["num_items"]
end

function conky_db_heartbeat_prototype_status()
    return db_heartbeat_status(hb_prototype_status)
end

function conky_db_heartbeat_live_status()
    return db_heartbeat_status(hb_live_status)
end

function conky_db_diis_prod_status()
    local status_icon = "${color #"
    if diis_cruncher_status.avg_exec_time > 30*60 or tonumber(diis_cruncher_status.last_import) > 10*3600 then
        status_icon = status_icon .. "cc0000}" -- red color
    elseif diis_cruncher_status.avg_exec_time > 25*60 or tonumber(diis_cruncher_status.last_import) > 2*3600 then
        status_icon = status_icon .. "cccc00}" -- yellow color
    elseif diis_cruncher_status.avg_exec_time > 0*60 and tonumber(diis_cruncher_status.last_import) > 0*3600 then
        status_icon = status_icon .. "00cc00}" -- green color
    else
        status_icon = status_icon .. "888888}" -- grey color (unknown)
    end
    if diis_cruncher_status.status == "deployed" then
        status_icon = status_icon .. "${font Entypo:size=24}▶${font}${color #888888}"
    elseif diis_cruncher_status.status == "paused" then
        status_icon = status_icon .. "${font Entypo:size=24}‖${font}${color #888888}"
    elseif diis_cruncher_status.status == "stopped" then
        status_icon = status_icon .. "${font Entypo:size=24}■${font}${color #888888}"
    elseif diis_cruncher_status.status == "wait4pause" or diis_cruncher_status.status == "wait4stop" then
        status_icon = status_icon .. "${font Entypo:size=24}⏳${font}${color #888888}"
    else
        status_icon = status_icon .. "${font Entypo:size=24}❓${font}${color #888888}"
    end
    return status_icon .. "${voffset -4} " .. string.format("%-20s", diis_cruncher_status.name) .. "${offset 30}" .. seconds_to_hms(diis_cruncher_status.avg_exec_time) .. "${color}"
end

function conky_db_crashtool_prod_idd_status()
    local last_import = tonumber(crashtool_prod_idd_status["last_import"])
    local color = "888888" -- grey color (unknown)
    if last_import > 120*60 then
        color = "cc0000" -- red color
    elseif last_import > 40*60 then
        color = "cccc00" -- yellow color
    elseif last_import > 0 then
        color = "00cc00" -- green color
    end
    return "${color #" .. color .. "}${font Entypo:size=24}▶${font}${color #888888}${voffset -4}" .. string.format(" CT prod: %-10s", crashtool_prod_idd_status["name"]) ..  "${offset  30}" .. seconds_to_hms(crashtool_prod_idd_status.last_import) .. "${color}"
end

function conky_db_crashtool_prod_mtbf_status()
    local last_import = tonumber(crashtool_prod_mtbf_status["last_import"])
    local color = "888888" -- grey color (unknown)
    if last_import > 30*60 then
        color = "cc0000" -- red color
    elseif last_import > 20*60 then
        color = "cccc00" -- yellow color
    elseif last_import > 0 then
        color = "00cc00" -- green color
    end
    return "${color #" .. color .. "}${font Entypo:size=24}▶${font}${color #888888}${voffset -4}" .. string.format(" CT prod: %-10s", crashtool_prod_mtbf_status["name"]) ..  "${offset  30}" .. seconds_to_hms(crashtool_prod_mtbf_status.last_import) .. "${color}"
end

function conky_db_crashtool_rca_status()
    local last_import = tonumber(crashtool_rca_status["last_import"])
    local color = "888888" -- grey color (unknown)
    if last_import > 30*60 then
        color = "cc0000" -- red color
    elseif last_import > 20*60 then
        color = "cccc00" -- yellow color
    elseif last_import > 0 then
        color = "00cc00" -- green color
    end
    return "${color #" .. color .. "}${font Entypo:size=24}▶${font}${color #888888}${voffset -4}" .. string.format(" CT rca: %-11s", crashtool_rca_status["name"]) ..  "${offset  30}" .. seconds_to_hms(crashtool_rca_status.last_import) .. "${color}"
end


-- print ("name\tlast_run\tavg_run_time\tnum_items\tstatus")
-- db_update()
-- print (table_as_string(hb_prototype_status))
-- print (table_as_string(hb_live_status))
-- print (table_as_string(diis_cruncher_status))
-- print (table_as_string(crashtool_prod_idd_status))
-- print (table_as_string(crashtool_prod_mtbf_status))
-- print (table_as_string(crashtool_rca_status))
-- 
-- print (conky_db_heartbeat_prototype_status())
-- print (conky_db_heartbeat_live_status())
-- print (conky_db_diis_prod_status())
-- print (conky_db_crashtool_prod_idd_status())
-- print (conky_db_crashtool_prod_mtbf_status())
-- print (conky_db_crashtool_rca_status())

