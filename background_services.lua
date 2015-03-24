-- vim: ts=4 sw=4 expandtab ai syntax=lua

--
-- Utility functions
--
function json_decode_file( file )
  local json = require( "json" )

  local t = {}
  for line in io.lines( file ) do
    t[#t + 1] = line
  end
  local str = table.concat( t, "\n" )

  return json.decode( str )
end


--
-- UI functions
--

local conky_firstrun = 1
local conky_isinitializing = 0
local cdh4_interval = 30
local db_interval   = 300
local settings = nil

function conky_init()
    if conky_isinitializing == 1 then
        return
    end
    conky_isinitializing = 1
    settings = json_decode_file("dotfiles/settings.json")
    conky_isinitializing = 0
end

-- This function triggers the update on the backend
-- we use the conky variable ${updates} mod interval to determine if we're to update
function conky_update()
    if settings == nil then
        conky_init()
        return
    end

    local updates      = tonumber(conky_parse("${updates}"))

    local cdh4_timer   = (updates % cdh4_interval)
    local db_timer     = (updates % db_interval)

    if ((cdh4_timer == 0) or (conky_firstrun == 1)) and not (settings == nil) then
        cdh4_update(settings.cdh4_settings)
    end --if cdh4_timer

    if ((db_timer == 0) or (conky_firstrun == 1)) and not (settings == nil) then
        db_update(settings.db_settings)
    end --if db_timer

    if not (settings == nil) then
        conky_firstrun = 0
    end
end
