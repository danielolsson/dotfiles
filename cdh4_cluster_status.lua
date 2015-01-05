-- vim: ts=4 sw=4 expandtab ai syntax=lua
--
-- Utility functions
--
function get_json_from_url( url, credentials )
    local credstring  = credentials.username .. ":" .. credentials.password
    local file = io.popen( "curl -s -u" .. credstring .. " '" .. url .. "' 2>/dev/null" )
    local output = file:read("*a")
    file:close()
    local json = require( "json" )
    return json.decode( output )
end

function url_decode(str)
  str = string.gsub (str, "+", " ")
  str = string.gsub (str, "%%(%x%x)",
      function(h) return string.char(tonumber(h,16)) end)
  str = string.gsub (str, "\r\n", "\n")
  return str
end

--
-- Backend functions
--

--
-- dfs_capacity, dfs_capacity_used
--
function cdh4_get_hdfs_status( hdfs_service_name, settings )
    local services_url   = settings.url .. "/clusters/" .. settings.clustername .. "/services/" .. hdfs_service_name .. "/metrics?metrics=dfs_capacity&metrics=dfs_capacity_used"
    local rawstatus = get_json_from_url( services_url, settings.credentials )
    local total
    local used
    for metricnr, metric in ipairs(rawstatus.items) do
        if metric.name == "dfs_capacity" then
            total = metric.data[#(metric.data)].value
        elseif metric.name == "dfs_capacity_used" then
            used = metric.data[#(metric.data)].value
        else
            print "Unknown hdfs metric!"
        end
    end
    return (used/total)*100
end

--
-- jvm_max_memory_mb_tasktracker_max, jvm_max_memory_mb_tasktracker_sum
--
function cdh4_get_mapreduce_status( mapreduce_service_name, settings )
    local services_url   = settings.url .. "/clusters/" .. settings.clustername .. "/services/" .. mapreduce_service_name .. "/metrics?metrics=jobs_running&metrics=jobs_preparing&metrics=maps_running&metrics=map_slots&metrics=reduces_running&metrics=reduce_slots&metrics=jvm_heap_used_mb_tasktracker_sum&metrics=jvm_heap_used_mb_tasktracker_max"
    local rawstatus = get_json_from_url( services_url, settings.credentials )
    local mr_status = {}
    for metricnr, metric in ipairs(rawstatus.items) do
        if metric.name == "jobs_running" then
            mr_status.jobs_running = metric.data[#(metric.data)].value
        elseif metric.name == "jobs_preparing" then
            mr_status.jobs_preparing = metric.data[#(metric.data)].value
        elseif metric.name == "maps_running" then
            mr_status.maps_running = metric.data[#(metric.data)].value
        elseif metric.name == "map_slots" then
            mr_status.map_slots = metric.data[#(metric.data)].value
        elseif metric.name == "reduces_running" then
            mr_status.reduces_running = metric.data[#(metric.data)].value
        elseif metric.name == "reduce_slots" then
            mr_status.reduce_slots = metric.data[#(metric.data)].value
        elseif metric.name == "jvm_heap_used_mb_tasktracker_sum" then
            mr_status.jvm_heap_used_mb_tasktracker_sum = metric.data[#(metric.data)].value
        elseif metric.name == "jvm_heap_used_mb_tasktracker_max" then
            mr_status.jvm_heap_used_mb_tasktracker_max = metric.data[#(metric.data)].value
        else
            print "Unknown mapreduce metric!"
        end
    end
    return mr_status
end

function cdh4_get_zookeeper_status( zookeeper_service_name, settings )
    local role_url   = settings.url .. "/clusters/" .. settings.clustername .. "/services/" .. zookeeper_service_name .. "/roles"
    local rawstatus = get_json_from_url( role_url, settings.credentials )
    local zk_status = { ["hosts"] = {} }

    for rolenr, role in ipairs(rawstatus.items) do
        local services_url   = settings.url .. "/clusters/" .. settings.clustername .. "/services/" .. settings.zookeeper_service_name .. "/roles/" .. role.name .. "/metrics?metrics=zk_server_connection_count"
        local rawstatus2 = get_json_from_url( services_url, settings.credentials )
        local zk_host_status = {}
        for metricnr, metric in ipairs(rawstatus2.items) do
            if metric.name == "zk_server_connection_count" and #(metric.data) > 0 then
                zk_host_status.zk_server_connection_count = metric.data[#(metric.data)].value
            else
                zk_host_status.zk_server_connection_count = -1
                print "Unknown zookeeper metric!"
            end
        end
        zk_host_status.healthSummary = role.healthSummary
        zk_status.hosts[role.hostRef.hostId] = zk_host_status
    end
    return zk_status
end

function cdh4_get_services_status( settings )
    local services_url   = settings.url .. "/clusters/" .. settings.clustername .. "/services"
    local rawstatus = get_json_from_url( services_url, settings.credentials )
    local allstatus = { }
    for servicenr, service in ipairs(rawstatus.items) do
        local status = {}
        if service.type == "HDFS" then
            local capacity
            capacity = cdh4_get_hdfs_status( service.name, settings )
            status = { name = service.name, status = service.healthSummary, hdfs_used = capacity }
        elseif service.type == "MAPREDUCE" then
            status = cdh4_get_mapreduce_status( service.name, settings )
            status.name = service.name
            status.status = service.healthSummary
        elseif service.type == "ZOOKEEPER" then
            status = cdh4_get_zookeeper_status( service.name, settings )
            status.name = service.name
            status.status = service.healthSummary
        else
            status = { name = service.name, status = service.healthSummary }
        end
        allstatus[service.type] = status
    end
    return allstatus
end

function cdh4_get_hosts_status( settings )
    local hosts_url = settings.url .. "/hosts/"
    local allhosts = get_json_from_url( hosts_url, settings.credentials )
    local status = { }
    for hostnr, host in ipairs(allhosts.items) do
        local hoststatus = get_json_from_url( hosts_url .. host.hostname, settings.credentials )
        status[host.hostname] = { status = hoststatus.healthSummary }
    end
    return status
end



--
-- UI functions
--

--
-- Fonts required:
-- StyleBats - http://img.dafont.com/dl/?f=style_bats
-- PizzaDude Bullets - http://img.dafont.com/dl/?f=pizzadude_bullets
-- DroidSansMono
--

--
-- Module local variables
-- Our backend functions communicate with the frontend through these variables
-- This is so that we can update the variables from http/json less frequently than the UI
--
local conky_start = 1
local servicestatus = {}
local hoststatus = {}
local clustername = ""

-- This function triggers the update on the backend
-- It should be called from another script with a timer - don't call it directly from conky!
function cdh4_update( settings )
    servicestatus = cdh4_get_services_status( settings )
    hoststatus = cdh4_get_hosts_status( settings )
    clustername = url_decode( settings.clustername )
end

-- This function triggers the update on the backend (called directly from conky)
-- we use the conky variable ${updates} mod interval to determine if we're to update
function conky_cdh4_parse_status()
    local updates      = tonumber(conky_parse("${updates}"))
    local interval     = 30
    timer = (updates % interval)
    if timer == 0 or conky_start == 1 then
        -- print ("Update # "..updates)
        -- print ("you will see this at conky start and then at " .. interval .. " cycle intervals")
        conky_start = nil
        servicestatus = cdh4_get_services_status()
        hoststatus = cdh4_get_hosts_status()
    end --if timer
end

--
-- Returns the service color from its name
--
function conky_cdh4_get_service_color( servicetype )
    if servicestatus[servicetype] == nil then return "${color #888888}" end
    local servicetypestatus = servicestatus[servicetype].status
    if     servicetypestatus == "GOOD" then return "${color #00cc00}"
    elseif servicetypestatus == "CONCERNING" then return "${color #cccc00}"
    else return "${color #cc0000}"
    end
end

-- Get the CDH4 cluster name
function conky_cdh4_get_cluster_name()
    return clustername
end

-- Get CDH4 service status
function conky_cdh4_get_service_status( servicetype )
    local servicename = "Unknown"
    if not (servicestatus[servicetype] == nil) then
        servicename = servicestatus[servicetype].name
    end
    return "${voffset 4}" .. conky_cdh4_get_service_color( servicetype ) .. "${font StyleBats:size=16}I${font}${color #cccccc}${voffset -4} " .. servicename .. "${color}"
end

-- Get the CDH4 HDFS status
function conky_cdh4_get_hdfs_status()
    return conky_cdh4_get_service_status( "HDFS" )
end

-- Get the CDH4 HDFS used
function conky_cdh4_get_hdfs_used()
    if not (servicestatus["HDFS"] == nil) then
        -- servicename = servicestatus["HDFS"].name
        if not (servicestatus["HDFS"].hdfs_used == nil) then
            return servicestatus["HDFS"].hdfs_used
        end
    end
    return 0
end

-- Get the CDH4 Mapreduce status
function conky_cdh4_get_mapreduce_status()
    return conky_cdh4_get_service_status( "MAPREDUCE" )
end

-- Get the CDH4 Mapreduce status
function conky_cdh4_get_mapreduce_jobs()
    result = ""
    if not (servicestatus["MAPREDUCE"] == nil) then
        if not (servicestatus["MAPREDUCE"].jobs_running == nil) then
            result = "J:" .. servicestatus["MAPREDUCE"].jobs_running
        end
        if not (servicestatus["MAPREDUCE"].jobs_preparing == nil) then
            result = result .. "/" .. servicestatus["MAPREDUCE"].jobs_preparing
        end
        if not (servicestatus["MAPREDUCE"].maps_running == nil) then
            result = result .. " M:" .. servicestatus["MAPREDUCE"].maps_running
        end
        if not (servicestatus["MAPREDUCE"].map_slots == nil) then
            result = result .. "/" .. servicestatus["MAPREDUCE"].map_slots
        end
        if not (servicestatus["MAPREDUCE"].reduces_running == nil) then
            result = result .. " R:" .. servicestatus["MAPREDUCE"].reduces_running
        end
        if not (servicestatus["MAPREDUCE"].reduce_slots == nil) then
            result = result .. "/" .. servicestatus["MAPREDUCE"].reduce_slots
        end
    end
    return result
end

-- Get the CDH4 Zookeeper status
function conky_cdh4_get_zookeeper_status()
    return conky_cdh4_get_service_status( "ZOOKEEPER" )
end

-- Get the number of CDH4 Zookeeper connections
function conky_cdh4_get_zookeeper_connections()
    local output = "${offset 20}${voffset 0}${color #cccccc}${offset 55}${color #888888}"
    for hostname, host in pairs(hoststatus) do
        local zk_hoststatus = servicestatus["ZOOKEEPER"].hosts[hostname]
        if not (zk_hoststatus == nil) then
            if not (zk_hoststatus.zk_server_connection_count == nil) then
                output = output .. zk_hoststatus.zk_server_connection_count
            else
                output = output .. " E "
            end
        else
            output = output .. "  "
        end
    end
    output = output .. "${color}"
    return output
end

-- Get the CDH4 Hue status
function conky_cdh4_get_hue_status()
    return conky_cdh4_get_service_status( "HUE" )
end

-- Get the CDH4 Hive status
function conky_cdh4_get_hive_status()
    return conky_cdh4_get_service_status( "HIVE" )
end

-- Returns the host's color
function conky_cdh4_get_host_color( hostname )
    local status = hoststatus[hostname].status
    if     status == "GOOD" then return "${color #00cc00}"
    elseif status == "CONCERNING" then return "${color #cccc00}"
    else return "${color #cc0000}"
    end
end

-- Get the CDH4 hosts status
function conky_cdh4_get_hosts_status()
    -- local output = "${voffset 4}"
    local output = "${voffset -3}${font DroidSansMono:size=12}"
    for hostname, host in pairs(hoststatus) do
        local hostnr = string.match(hostname, 'seldcdh00([0-5]).corpusers.net')
        -- print (hostnr)
        -- output = output .. conky_cdh4_get_host_color( hostname ) .. "${voffset -3}${font PizzaDude Bullets:size=12}8${offset 12}${font}${color}"
        -- Numbers in double circles (Enclosed Alphanumerics - see http://www.unicode.org/charts/PDF/U2460.pdf)
        -- Double circled one starts on U+24F5
        -- Negative circled one starts on U+278A
        output = output .. conky_cdh4_get_host_color( hostname ) .. hostnr .. "${offset 12}${color}"
        -- output = output .. conky_cdh4_get_host_color( hostname ) .. "${voffset -3}" .. string.char(hostnr) .. "${offset 12}${font}${color}"
    end
    return output .. "${font}"
end


--
-- cdh4_update()
--
