--[[
  IMM_TakeHome — Exotic Delivery Pod cargo to YOUR ITEMS.

  Pair with a Take Home EXMOD (remelt). This script copies live pod / overflow
  stacks into YOUR ITEMS before vanilla deletes world items.
  Config: config/TakeHome.ini (Enabled=0 to disable).
]]

local MOD_NAME = "IMM_TakeHome"
local POD_CLASSES = {
    "BP_Exotic_Delivery_Ship_C",
    "BP_ExoticDeliveryShip_C",
}
local OVERFLOW_CLASSES = {
    "BP_Overflow_Bag_C",
    "BP_Overflow_Bag_NoPhysics_C",
}
local STACK_PROP = 7
local DURABILITY_PROP = 6
local LINK_PROP = 13
local SPOIL_PROP = 12
local VANILLA_STACK = {
    Fiber = 200,
    Berry = 100,
    raw_meat = 20,
    bone = 100,
    Fur = 100,
    Leather = 100,
    Stick = 100,
    Oxite = 50,
    Carrot = 100,
    Lily = 100,
    Stone = 100,
}
local FALLBACK_SPOIL_TIME = {
    Berry = 1600,
    Carrot = 1600,
    Pumpkin = 1600,
    Lily = 1600,
    raw_meat = 1200,
    Raw_Meat = 1200,
}

local cfg = { enabled = true }
local state = {
    granted = {},
    dt = {},
    stack_cap = {},
    internal_remove = false,
}

local function mod_dir()
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", "")
    return src:match("^(.*)[/\\]Scripts[/\\]main%.lua$") or "."
end

local function log(_msg)
end

local function write_grant(_payload)
end

local function pget(fn)
    local ok, a, b, c, d = pcall(fn)
    if ok then
        return a, b, c, d
    end
    return nil
end

local function unwrap(v)
    if v == nil then
        return nil
    end
    local got = pget(function()
        if type(v) == "userdata" and v.get then
            return v:get()
        end
        return v
    end)
    return got
end

local function fname_str(rn)
    if rn == nil then
        return nil
    end
    if type(rn) == "string" then
        return rn
    end
    return pget(function()
        if rn.ToString then
            return rn:ToString()
        end
        return tostring(rn)
    end)
end

local function ufull(obj)
    return pget(function()
        return obj:GetFullName()
    end)
end

local function item_row(item)
    if item == nil then
        return nil
    end
    return pget(function()
        local static = item.ItemStaticData or item.Item
        if static == nil then
            return fname_str(item.RowName)
        end
        return fname_str(static.RowName)
    end)
end

local function guid_str(g)
    if g == nil then
        return nil
    end
    if type(g) == "string" then
        return g
    end
    local s = fname_str(g)
    if s and s ~= "" and s ~= "userdata" then
        return s
    end
    return pget(function()
        if g.ToString then
            return g:ToString()
        end
    end) or pget(function()
        if g.A ~= nil then
            return string.format("%08X%08X%08X%08X", g.A, g.B, g.C, g.D)
        end
    end)
end

local function new_guid()
    local hex = "0123456789ABCDEF"
    local out = {}
    for i = 1, 32 do
        local n = math.random(1, 16)
        out[i] = hex:sub(n, n)
    end
    return table.concat(out)
end

local function arr_num(a)
    if a == nil then
        return 0
    end
    return tonumber(
        pget(function()
            return a:GetArrayNum()
        end)
            or pget(function()
                return a:GetNum()
            end)
            or pget(function()
                return a.Num
            end)
            or pget(function()
                return #a
            end)
            or 0
    ) or 0
end

local function arr_each(a, fn)
    if a == nil then
        return
    end
    local ok = pcall(function()
        a:ForEach(function(idx, elem)
            fn(idx, unwrap(elem) or elem)
        end)
    end)
    if ok then
        return
    end
    local n = arr_num(a)
    for i = 1, n do
        local elem = pget(function()
            return a[i]
        end)
        fn(i, unwrap(elem) or elem)
    end
end

local function parse_ini()
    local path = mod_dir() .. "/../config/TakeHome.ini"
    local f = io.open(path, "r")
    if not f then
        path = mod_dir() .. "/config/TakeHome.ini"
        f = io.open(path, "r")
    end
    local flags = {}
    if f then
        for line in f:lines() do
            line = line:gsub("%s*;.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
            local k, v = line:match("^([%w_]+)%s*=%s*(%S+)$")
            if k then
                flags[k:lower()] = v
            end
        end
        f:close()
    end
    local v = flags.enabled
    if v ~= nil then
        cfg.enabled = v == "1" or v:lower() == "true" or v:lower() == "yes"
    end
    log("enabled=" .. tostring(cfg.enabled))
end

local CATALOG = { spoil_time = FALLBACK_SPOIL_TIME, container = {} }

local function catalog_get(map, row)
    if map == nil or row == nil or row == "" then
        return nil
    end
    local v = map[row]
    if v ~= nil then
        return v
    end
    local low = string.lower(row)
    v = map[low]
    if v ~= nil then
        return v
    end
    for k, val in pairs(map) do
        if type(k) == "string" and string.lower(k) == low then
            return val
        end
    end
    return nil
end

local function load_catalog()
    local paths = {
        mod_dir() .. "/Scripts/catalog.lua",
        mod_dir() .. "/catalog.lua",
    }
    local last_err = nil
    for _, path in ipairs(paths) do
        local ok, cat = pcall(dofile, path)
        if ok and type(cat) == "table" then
            CATALOG.spoil_time = cat.spoil_time or CATALOG.spoil_time
            CATALOG.container = cat.container or CATALOG.container or {}
            local nt, nc = 0, 0
            for _ in pairs(CATALOG.spoil_time or {}) do
                nt = nt + 1
            end
            for _ in pairs(CATALOG.container or {}) do
                nc = nc + 1
            end
            log("catalog " .. path .. " spoil_time=" .. tostring(nt) .. " container=" .. tostring(nc))
            return
        end
        last_err = cat
    end
    log("catalog.lua skipped: " .. tostring(last_err))
end

local function inv_info_name(inv)
    local h = pget(function()
        return inv:GetInventoryInfo()
    end)
    if h == nil then
        return nil
    end
    return fname_str(pget(function()
        return h.RowName
    end)) or fname_str(pget(function()
        local rh = h.InventoryInfoRowHandle or h.RowHandle
        return rh and rh.RowName
    end))
end

local function inv_id_from_value(v)
    if v == nil then
        return nil
    end
    if type(v) == "number" then
        return v
    end
    return tonumber(pget(function()
        return v.ID or v.Value or v.A or v.UniqueID or v.UniqueId or v
    end))
end

-- GetInventoryID() is the InventoryID enum (General, Backpack, ...), not the
-- runtime id stored on InventoryContainer_LinkedInventoryId (48, 725, ...).
local function inv_id_candidates(inv)
    inv = unwrap(inv) or inv
    local out, seen = {}, {}
    local function add(v)
        local n = inv_id_from_value(v)
        if n ~= nil and not seen[n] then
            seen[n] = true
            table.insert(out, n)
        end
    end
    add(pget(function()
        return inv.InventoryUniqueId or inv.InventoryUniqueID
    end))
    add(pget(function()
        return inv.UniqueInventoryId or inv.UniqueInventoryID
    end))
    add(pget(function()
        return inv.UniqueID or inv.UniqueId
    end))
    add(pget(function()
        return inv.InventoryInstanceId or inv.InstanceID or inv.InstanceId
    end))
    return out
end

local function inv_numeric_id(inv)
    local best = nil
    for _, n in ipairs(inv_id_candidates(inv)) do
        if n >= 2 and (best == nil or n > best) then
            best = n
        end
    end
    return best
end

local function is_attach_info(name)
    name = string.lower(tostring(name or ""))
    return name:find("attachment", 1, true) ~= nil
end

local ATTACH_INFO_KEYS = {
    { "Sledgehammer", "Sledgehammer_Attachment" },
    { "Pickaxe", "Pickaxe_Attachment" },
    { "Sickle", "Sickle_Attachment" },
    { "Hammer", "Hammer_Attachment" },
    { "Knife", "Knife_Attachment" },
    { "Spear", "Spear_Attachment" },
    { "Axe", "Axe_Attachment" },
    { "Head", "Head_Attachment" },
    { "Chest", "Body_Attachment" },
    { "Arms", "Arms_Attachment" },
    { "Legs", "Legs_Attachment" },
    { "Feet", "Feet_Attachment" },
}

local function attach_info_for_row(row)
    row = tostring(row or "")
    local mapped = catalog_get(CATALOG.container or {}, row)
    if mapped ~= nil and mapped ~= "" and mapped ~= "None" then
        return mapped
    end
    for _, pair in ipairs(ATTACH_INFO_KEYS) do
        if row:find(pair[1], 1, true) then
            return pair[2]
        end
    end
    return nil
end

local function is_attachment_row(row)
    row = tostring(row or "")
    return row:find("Attachment", 1, true) ~= nil or row:find("Module_", 1, true)
end

local function index_inv(inv)
    inv = unwrap(inv) or inv
    if inv == nil then
        return nil
    end
    state.scanned_invs = state.scanned_invs or {}
    state.inv_by_id = state.inv_by_id or {}
    state.inv_by_info = state.inv_by_info or {}
    local k = tostring(inv)
    for _, row in ipairs(state.scanned_invs) do
        if row.k == k then
            return row
        end
    end
    local info_row = inv_info_name(inv)
    local ids = inv_id_candidates(inv)
    local n = 0
    if is_attach_info(info_row) then
        n = tonumber(pget(function()
            return inv:GetNumItems()
        end)) or 0
    end
    local row = { k = k, inv = inv, info = info_row, ids = ids, n = n }
    table.insert(state.scanned_invs, row)
    for _, id in ipairs(ids) do
        if id >= 2 then
            state.inv_by_id[id] = inv
        end
    end
    if info_row and info_row ~= "" then
        local list = state.inv_by_info[info_row]
        if list == nil then
            list = {}
            state.inv_by_info[info_row] = list
        end
        table.insert(list, inv)
    end
    return row
end

local function find_inv_by_id(link_id)
    if link_id == nil or tonumber(link_id) == nil or tonumber(link_id) < 2 then
        return nil
    end
    link_id = tonumber(link_id)
    local mapped = state.inv_by_id and state.inv_by_id[link_id]
    if mapped ~= nil then
        return mapped
    end
    for _, row in ipairs(state.scanned_invs or {}) do
        for _, id in ipairs(row.ids or {}) do
            if id == link_id then
                return row.inv
            end
        end
    end
    return nil
end

local function items_in_inv(inv)
    local out = {}
    inv = unwrap(inv) or inv
    if inv == nil then
        return out
    end
    arr_each(pget(function()
        return inv:GetAllItems()
    end), function(_, item)
        item = unwrap(item) or item
        if item ~= nil then
            table.insert(out, item)
        end
    end)
    return out
end

local function attach_scan_blob()
    local bits = {}
    for _, row in ipairs(state.scanned_invs or {}) do
        if is_attach_info(row.info) or row.attach then
            table.insert(
                bits,
                tostring(row.info or "info?")
                    .. " ids="
                    .. table.concat(row.ids or {}, ",")
                    .. " n="
                    .. tostring(row.n)
            )
        end
    end
    return table.concat(bits, "; ")
end

local function read_inv(inv, info, tag)
    inv = unwrap(inv) or inv
    if inv == nil then
        return
    end
    state.seen_inv = state.seen_inv or {}
    local ik = tostring(inv)
    if state.seen_inv[ik] then
        return
    end
    state.seen_inv[ik] = true
    index_inv(inv)
    local num = pget(function()
        return inv:GetNumItems()
    end)
    local info_row = inv_info_name(inv)
    local all = pget(function()
        return inv:GetAllItems()
    end)
    local nall = arr_num(all)
    local nslots = (type(num) == "number" and num) or nall or 0
    info.slot_n = info.slot_n + (tonumber(nslots) or 0)
    local row = {
        name = ufull(inv),
        n = nslots,
        info = info_row,
        nall = nall,
        tag = tag,
    }
    table.insert(info.invs, row)
    local function take_item(item)
        local name = item_row(item)
        if name and name ~= "" and name ~= "Player_Fists" and name ~= "Player_Fist" then
            local stack, dur, spoil = nil, nil, nil
            arr_each(pget(function()
                return item.ItemDynamicData
            end), function(_, e)
                local pt = pget(function()
                    return e.PropertyType
                end)
                local val = pget(function()
                    return e.Value
                end)
                local pts = tostring(pt or "")
                if pt == STACK_PROP then
                    stack = val
                elseif pt == DURABILITY_PROP or pts == "Durability" then
                    dur = val
                elseif pt == SPOIL_PROP or pts == "Decayable_CurrentSpoilTime" then
                    spoil = val
                end
            end)
            table.insert(info.items, {
                row = name,
                inv = info_row or tag or row.name,
                stack = stack,
            })
            table.insert(state.live, {
                row = name,
                inv = info_row or tag or row.name,
                iname = row.name,
                tag = tag,
                inv_obj = inv,
                actor = info.current_actor,
                item = item,
                stack = stack,
                dur = dur,
                spoil = spoil,
                ship = info.current_ship,
                owner = pget(function()
                    return item.ItemOwnerLookupId
                end),
                guid = guid_str(pget(function()
                    return item.DatabaseGUID
                end)) or "",
            })
        end
    end
    local before = #info.items
    arr_each(all, function(_, item)
        take_item(item)
    end)
    if #info.items == before and type(num) == "number" and num > 0 and num < 80 then
        for i = 0, num do
            take_item(pget(function()
                return inv:GetItem(i)
            end) or pget(function()
                return inv:GetItemAt(i)
            end) or pget(function()
                local s = inv:GetSlot(i)
                return s and (s.Item or s.ItemData or s)
            end))
        end
    end
end

local function vec3(v)
    if v == nil then
        return nil
    end
    local x = pget(function()
        return v.X or v.x
    end)
    local y = pget(function()
        return v.Y or v.y
    end)
    local z = pget(function()
        return v.Z or v.z
    end)
    if x == nil then
        return nil
    end
    return { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0 }
end

local function dist2(a, b)
    if a == nil or b == nil then
        return 1e18
    end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

local function ship_id(name)
    local s = tostring(name or "")
    return s:match("BP_Overflow_Bag_C_%d+")
        or s:match("BP_Exotic_Delivery_Ship_C_%d+")
        or s:match("BP_ExoticDeliveryShip_C_%d+")
end

local function unique_live()
    local seen, out = {}, {}
    local function rank(it)
        local tag = string.lower(tostring(it.tag or ""))
        local blob = string.lower(table.concat({
            tostring(it.inv or ""),
            " ",
            tostring(it.iname or ""),
            " ",
            tag,
        }, ""))
        if blob:find("overflow", 1, true) then
            return 3
        end
        if blob:find("exotic_delivery", 1, true) or tag:find("pod", 1, true) then
            return 2
        end
        return 1
    end
    for _, it in ipairs(state.live or {}) do
        local k = tostring(it.item)
        if it.item ~= nil then
            local idx = seen[k]
            if idx == nil then
                seen[k] = #out + 1
                table.insert(out, it)
            elseif rank(it) > rank(out[idx]) then
                out[idx] = it
            end
        end
    end
    table.sort(out, function(a, b)
        return rank(a) > rank(b)
    end)
    return out
end

local function scan_actor_inventories(actor, info, tag)
    actor = unwrap(actor) or actor
    if actor == nil then
        return
    end
    pcall(function()
        if actor.GetAllInventories then
            arr_each(actor:GetAllInventories(true), function(_, inv)
                read_inv(inv, info, tag)
            end)
        end
    end)
    local c = pget(function()
        return actor.Inventory or actor.InventoryComponent
    end)
    pcall(function()
        arr_each(c and (c.Inventories or c.InventoryList), function(_, inv)
            read_inv(inv, info, tag .. ".Inventories")
        end)
    end)
    pcall(function()
        if c and c.GetInventories then
            arr_each(c:GetInventories(), function(_, inv)
                read_inv(inv, info, tag .. ".GetInventories")
            end)
        end
    end)
    pcall(function()
        if c and c.GetInventory then
            read_inv(c:GetInventory("Exotic_Delivery_Ship"), info, "Exotic_Delivery_Ship")
            read_inv(c:GetInventory("Overflow_Bag"), info, "Overflow_Bag")
            for _, pair in ipairs(ATTACH_INFO_KEYS) do
                read_inv(c:GetInventory(pair[2]), info, "attach")
            end
            read_inv(c:GetInventory("Tool_Attachment"), info, "attach")
            read_inv(c:GetInventory("Slotable"), info, "attach")
            local seen_name = {}
            for _, name in pairs(CATALOG.container or {}) do
                if type(name) == "string" and name ~= "" and not seen_name[name] then
                    seen_name[name] = true
                    read_inv(c:GetInventory(name), info, "attach")
                end
            end
        end
    end)
end

local function read_named_attach_invs(c, info, tag)
    if c == nil or c.GetInventory == nil then
        return
    end
    pcall(function()
        read_inv(c:GetInventory("Exotic_Delivery_Ship"), info, "Exotic_Delivery_Ship")
        read_inv(c:GetInventory("Overflow_Bag"), info, "Overflow_Bag")
        for _, pair in ipairs(ATTACH_INFO_KEYS) do
            read_inv(c:GetInventory(pair[2]), info, "attach")
        end
        read_inv(c:GetInventory("Tool_Attachment"), info, "attach")
        read_inv(c:GetInventory("Slotable"), info, "attach")
        local mapped = {}
        for _, name in pairs(CATALOG.container or {}) do
            if type(name) == "string" and name ~= "" and not mapped[name] then
                mapped[name] = true
                read_inv(c:GetInventory(name), info, "attach")
            end
        end
    end)
end

local function scan_inventory_component(c, info, tag)
    c = unwrap(c) or c
    if c == nil then
        return
    end
    pcall(function()
        arr_each(c.Inventories or c.InventoryList, function(_, inv)
            inv = unwrap(inv) or inv
            local n = tonumber(pget(function()
                return inv:GetNumItems()
            end)) or 0
            local iname = inv_info_name(inv)
            if n <= 2 or is_attach_info(iname) then
                read_inv(inv, info, tag)
            else
                index_inv(inv)
            end
        end)
    end)
    pcall(function()
        if c.GetInventories then
            arr_each(c:GetInventories(), function(_, inv)
                inv = unwrap(inv) or inv
                local n = tonumber(pget(function()
                    return inv:GetNumItems()
                end)) or 0
                if n <= 2 or is_attach_info(inv_info_name(inv)) then
                    read_inv(inv, info, tag)
                else
                    index_inv(inv)
                end
            end)
        end
    end)
end

local function scan_all_inventory_components(info)
    local comps = pget(function()
        return FindAllOf("InventoryComponent")
    end)
    if type(comps) ~= "table" then
        comps = comps and { comps } or {}
    end
    info.comp_n = #comps
    local n = 0
    for _, c in ipairs(comps) do
        n = n + 1
        if n > 80 then
            break
        end
        scan_inventory_component(c, info, "comp")
    end
end

local function snapshot_cargo()
    local pc = pget(function()
        return FindFirstOf("BP_IcarusPlayerControllerSurvival_C")
    end) or pget(function()
        return FindFirstOf("IcarusPlayerControllerSurvival")
    end)
    state.live = {}
    state.seen_inv = {}
    state.scanned_invs = {}
    state.inv_by_id = {}
    state.inv_by_info = {}
    local info = {
        pc = ufull(pc),
        inv_n = 0,
        slot_n = 0,
        items = {},
        actors = {},
        invs = {},
    }
    if pc == nil then
        info.err = "no player controller"
        return info
    end
    scan_actor_inventories(pc, info, "player")
    local inventories = pget(function()
        return pc:GetAllInventories(true)
    end) or pget(function()
        return pc:GetAllInventories(false)
    end) or pget(function()
        return pc:GetAllInventories()
    end)
    info.inv_n = arr_num(inventories)
    arr_each(inventories, function(_, inv)
        info.current_ship = nil
        read_inv(inv, info, "player")
    end)
    local pawn = pget(function()
        if pc.K2_GetPawn then
            return pc:K2_GetPawn()
        end
        return pc.Pawn or pc.AcknowledgedPawn
    end)
    if pawn ~= nil then
        scan_actor_inventories(pawn, info, "pawn")
        arr_each(pget(function()
            return pawn:GetAllInventories(true)
        end) or pget(function()
            return pawn:GetAllInventories()
        end), function(_, inv)
            read_inv(inv, info, "pawn")
        end)
    end
    scan_all_inventory_components(info)
    local pawn_loc = vec3(pget(function()
        if pawn and pawn.K2_GetActorLocation then
            return pawn:K2_GetActorLocation()
        end
    end))
    local pods = {}
    for _, cls in ipairs(POD_CLASSES) do
        local found = pget(function()
            return FindAllOf(cls)
        end)
        if found ~= nil then
            if type(found) ~= "table" then
                found = { found }
            end
            for _, ship in ipairs(found) do
                ship = unwrap(ship) or ship
                table.insert(pods, ship)
                table.insert(info.actors, { class = cls, name = ufull(ship) })
            end
        else
            table.insert(info.actors, { class = cls })
        end
    end
    local closest, closest_d = nil, 1e18
    info.ships = {}
    for _, ship in ipairs(pods) do
        local sloc = vec3(pget(function()
            if ship.K2_GetActorLocation then
                return ship:K2_GetActorLocation()
            end
        end))
        local d = dist2(pawn_loc, sloc)
        local sname = ufull(ship) or ""
        local sid = ship_id(sname) or sname
        table.insert(info.ships, { name = sname, id = sid, dist = d })
        if closest == nil or d < closest_d then
            closest_d = d
            closest = sid
        end
    end
    state.closest_ship = closest
    info.closest_ship = closest
    for _, ship in ipairs(pods) do
        local sname = ufull(ship) or ""
        info.current_ship = ship_id(sname) or sname
        scan_actor_inventories(ship, info, "pod")
    end
    info.current_ship = nil
    local overflows = {}
    for _, cls in ipairs(OVERFLOW_CLASSES) do
        local found = pget(function()
            return FindAllOf(cls)
        end)
        if found ~= nil then
            if type(found) ~= "table" then
                found = { found }
            end
            for _, bag in ipairs(found) do
                bag = unwrap(bag) or bag
                table.insert(overflows, bag)
                table.insert(info.actors, { class = cls, name = ufull(bag) })
            end
        end
    end
    info.overflow_n = #overflows
    state.last_overflow_actors = overflows
    for _, bag in ipairs(overflows) do
        local bname = ufull(bag) or ""
        info.current_ship = ship_id(bname) or bname
        info.current_actor = bag
        scan_actor_inventories(bag, info, "overflow")
        local c = pget(function()
            return bag.Inventory or bag.InventoryComponent
        end)
        pcall(function()
            if c and c.GetInventory then
                read_inv(c:GetInventory("Overflow_Bag"), info, "Overflow_Bag")
            end
        end)
        info.current_actor = nil
    end
    info.current_ship = nil
    local all_inv = pget(function()
        return FindAllOf("Inventory")
    end)
    if type(all_inv) ~= "table" then
        all_inv = all_inv and { all_inv } or {}
    end
    info.world_inv_n = #all_inv
    local scanned = 0
    for _, inv in ipairs(all_inv) do
        scanned = scanned + 1
        if scanned > 400 then
            break
        end
        inv = unwrap(inv) or inv
        local iname = ufull(inv) or ""
        local low = iname:lower()
        if low:find("metainventory", 1, true) or low:find("playerdatacomponent", 1, true) then
            -- skip station bag
        else
            local info_row = inv_info_name(inv) or ""
            local info_low = tostring(info_row):lower()
            if low:find("exotic_delivery", 1, true)
                or low:find("exoticdelivery", 1, true)
                or info_low == "exotic_delivery_ship"
                or info_low:find("exotic_delivery", 1, true)
            then
                info.current_ship = ship_id(iname) or info_row
                read_inv(inv, info, "world")
            elseif (info.overflow_n or 0) == 0
                and (info_low == "overflow_bag"
                    or low:find("overflow_bag", 1, true)
                    or low:find("bp_overflow_bag", 1, true))
            then
                info.current_ship = ship_id(iname) or info_row
                read_inv(inv, info, "world")
            else
                index_inv(inv)
            end
        end
    end
    info.current_ship = nil
    info.attach_blob = attach_scan_blob()
    info.live_n = #(state.live or {})
    log(
        "snapshot player_inv="
            .. tostring(info.inv_n)
            .. " world="
            .. tostring(info.world_inv_n or 0)
            .. " comps="
            .. tostring(info.comp_n or 0)
            .. " live="
            .. tostring(info.live_n)
    )
    return info
end

local function on_station()
    local n = string.lower(tostring(pget(function()
        local w = FindFirstOf("World")
        if w == nil then
            return ""
        end
        if w.GetMapName then
            return w:GetMapName()
        end
        return w:GetName()
    end) or ""))
    return n:find("station", 1, true) ~= nil
end

local function skip_row(row)
    if not row or row == "" then
        return true
    end
    if row == "Player_Fist" or row == "Player_Fists" then
        return true
    end
    if row:find("EnviroSuit", 1, true) or row:sub(1, 5) == "Skin_" or row:find("Spacesuit", 1, true) then
        return true
    end
    return false
end

local function is_overflow_cargo(it)
    local blob = string.lower(table.concat({
        tostring(it.inv or ""),
        " ",
        tostring(it.iname or ""),
        " ",
        tostring(it.tag or ""),
    }, ""))
    return blob:find("overflow_bag", 1, true)
        or blob:find("bp_overflow_bag", 1, true)
        or tostring(it.tag or ""):lower():find("overflow", 1, true) ~= nil
end

local function is_ship_cargo(it)
    local inv = string.lower(tostring(it.inv or ""))
    local iname = string.lower(tostring(it.iname or ""))
    local tag = string.lower(tostring(it.tag or ""))
    local blob = inv .. " " .. iname .. " " .. tag
    if is_overflow_cargo(it) then
        return true
    end
    if blob:find("removeonly", 1, true) then
        return false
    end
    if inv == "dropship_meta" or blob:find("dropship_meta", 1, true) then
        return false
    end
    if inv == "dropship_equipment" or blob:find("dropship_equipment", 1, true) then
        return false
    end
    if inv == "exotic_delivery_ship" or blob:find("exotic_delivery", 1, true) then
        return true
    end
    if blob:find("exoticdelivery", 1, true) then
        return true
    end
    if tag == "pod" or tag:find("pod.", 1, true) then
        return true
    end
    return false
end

local function skip_grant_why(it)
    if skip_row(it.row) then
        return "blocked"
    end
    if tostring(it.tag or ""):lower() == "attach" and not is_ship_cargo(it) then
        return "nested_attach"
    end
    local blob = (tostring(it.inv or "") .. " " .. tostring(it.iname or "")):lower()
    if blob:find("metainventory", 1, true) or blob:find("playerdatacomponent", 1, true) then
        return "meta_inv"
    end
    if not is_ship_cargo(it) then
        return "not_ship_cargo"
    end
    if is_overflow_cargo(it) then
        if state.spawned_overflow ~= nil and it.actor ~= nil then
            local spawned = state.spawned_overflow
            local same = it.actor == spawned
            if not same then
                local a = ufull(it.actor) or ""
                local b = ufull(spawned) or ""
                same = a ~= "" and a == b
            end
            if not same then
                return "other_overflow"
            end
        end
        return nil
    end
    local closest = state.closest_ship
    local ship = it.ship
    local owner = tonumber(it.owner)
    if owner == nil then
        owner = -1
    end
    if ship and closest and ship ~= closest and owner == 0 then
        return "other_ship"
    end
    return nil
end

local function foreach_dyn(item, fn)
    arr_each(pget(function()
        return item.ItemDynamicData
    end), function(idx, e)
        fn(idx, e, pget(function()
            return e.PropertyType
        end), pget(function()
            return e.Value
        end))
    end)
end

local function dyn_stack(item)
    local n = 1
    foreach_dyn(item, function(_, _, pt, val)
        if pt == STACK_PROP then
            n = tonumber(val) or 1
        end
    end)
    return n
end

local function dyn_has_durability(item)
    local found = false
    foreach_dyn(item, function(_, _, pt)
        if pt == DURABILITY_PROP or tostring(pt or "") == "Durability" then
            found = true
        end
    end)
    return found
end

local function set_dyn_stack(item, n)
    foreach_dyn(item, function(_, e, pt)
        if pt == STACK_PROP then
            pcall(function()
                e.Value = n
            end)
        end
    end)
end

local function dyn_val(item, want)
    local n = nil
    foreach_dyn(item, function(_, _, pt, val)
        local pts = tostring(pt or "")
        if pt == want or pts == want then
            n = val
        end
    end)
    return n
end

local function dyn_props_blob(item)
    local parts = {}
    foreach_dyn(item, function(_, _, pt, val)
        table.insert(parts, tostring(pt) .. "=" .. tostring(val))
    end)
    return table.concat(parts, " ")
end

local function dyn_link(item)
    local n = nil
    foreach_dyn(item, function(_, _, pt, val)
        local pts = tostring(pt or "")
        if pt == LINK_PROP
            or pts == "InventoryContainer_LinkedInventoryId"
            or pts:find("LinkedInventory", 1, true)
        then
            n = tonumber(val)
        end
    end)
    return n
end

local function set_dyn_named(item, want, val)
    foreach_dyn(item, function(_, e, pt)
        local pts = tostring(pt or "")
        if pt == want or pts == want then
            pcall(function()
                e.Value = val
            end)
        end
    end)
end

local function set_dyn_link(item, val)
    set_dyn_named(item, LINK_PROP, val)
    set_dyn_named(item, "InventoryContainer_LinkedInventoryId", val)
end

local function dyn_spoil(item)
    local n = nil
    foreach_dyn(item, function(_, _, pt, val)
        local pts = tostring(pt or "")
        if pt == SPOIL_PROP or pts == "Decayable_CurrentSpoilTime" then
            n = tonumber(val)
        end
    end)
    return n
end

local function item_guid_hex(item)
    return guid_str(pget(function()
        return item.DatabaseGUID
    end)) or ""
end

local function meta_bag_items(pdc)
    local out = {}
    if pdc == nil then
        return out
    end
    local function take(a)
        arr_each(a, function(_, item)
            item = unwrap(item) or item
            if item ~= nil then
                table.insert(out, item)
            end
        end)
    end
    take(pget(function()
        return pdc:GetMetaInventoryItems()
    end))
    if #out > 0 then
        return out
    end
    take(pget(function()
        local inv = pdc.MetaInventory or pdc.OfflineMetaInventory
        return inv and (inv.Items or inv.InventoryItems or inv)
    end))
    if #out > 0 then
        return out
    end
    take(pget(function()
        return pdc.MetaInventoryItems or pdc.MetaItems
    end))
    return out
end

local function pick_pdc_and_bag(pc, quiet)
    local seen, pdcs = {}, {}
    local function add(obj)
        obj = unwrap(obj) or obj
        if obj == nil then
            return
        end
        local k = tostring(obj)
        if seen[k] then
            return
        end
        seen[k] = true
        table.insert(pdcs, obj)
    end
    local found = pget(function()
        return pc.PlayerDataComponent
    end) or pget(function()
        return pc:GetPlayerDataComponent()
    end)
    add(found)
    local all = pget(function()
        return FindAllOf("PlayerDataComponent")
    end)
    if type(all) ~= "table" then
        all = all and { all } or {}
    end
    for _, obj in ipairs(all) do
        add(obj)
    end
    local best, best_bag, best_n = found, {}, -1
    for _, pdc in ipairs(pdcs) do
        local bag = meta_bag_items(pdc)
        if not quiet then
            log("pdc n=" .. tostring(#bag) .. " " .. tostring(ufull(pdc) or "?"))
        end
        if #bag > best_n then
            best_n = #bag
            best = pdc
            best_bag = bag
        end
    end
    if best == nil then
        best = found
        best_bag = meta_bag_items(found)
    end
    return best, best_bag or {}
end

local function stack_key(it)
    return table.concat({
        tostring(it.row),
        tostring(it.stack),
        tostring(it.owner),
    }, "|")
end

local function find_named_datatable(needle)
    if state.dt[needle] ~= nil then
        if state.dt[needle] == false then
            return nil
        end
        return state.dt[needle]
    end
    local function accept(obj)
        obj = unwrap(obj) or obj
        if obj == nil then
            return nil
        end
        local n = ufull(obj) or ""
        if n == "" or not n:find(needle, 1, true) then
            return nil
        end
        state.dt[needle] = obj
        log("dt " .. needle .. " " .. n)
        return obj
    end
    local paths = {
        "/Game/Data/Traits/D_Itemable.D_Itemable",
        "/Game/Data/Items/D_Itemable.D_Itemable",
        "/Game/Data/Items/D_ItemsStatic.D_ItemsStatic",
        "/Game/Data/Traits/D_ItemsStatic.D_ItemsStatic",
    }
    for _, path in ipairs(paths) do
        if path:find(needle, 1, true) then
            local hit = accept(pget(function()
                return StaticFindObject(path)
            end))
            if hit then
                return hit
            end
        end
    end
    local hit = accept(pget(function()
        return FindFirstOf(needle)
    end))
    if hit then
        return hit
    end
    local all = pget(function()
        return FindAllOf("DataTable")
    end)
    if type(all) ~= "table" then
        all = all and { all } or {}
    end
    for _, dt in ipairs(all) do
        hit = accept(dt)
        if hit then
            return hit
        end
    end
    state.dt[needle] = false
    log("dt " .. needle .. " missing")
    return nil
end

local function dt_find_row(dt, name)
    if dt == nil or not name or name == "" then
        return nil
    end
    return pget(function()
        return dt:FindRow(name)
    end) or pget(function()
        return dt:GetRow(name)
    end) or pget(function()
        local map = dt.RowMap
        return map and map[name]
    end)
end

local function max_from_itemable_enum(iname)
    local e = pget(function()
        return StaticFindObject("/Script/Icarus.Default__ItemableEnum")
    end) or pget(function()
        return FindFirstOf("ItemableEnum")
    end)
    if e == nil then
        return nil
    end
    local handle = pget(function()
        return e:MakeLiteralItemable(iname)
    end) or pget(function()
        return e:MakeItemable(iname)
    end)
    local st = pget(function()
        return e:GetItemableStruct(handle)
    end)
    return tonumber(pget(function()
        return st.MaxStack
    end))
end

local function itemable_max_from_dt(iname)
    local cap = tonumber(pget(function()
        local row = dt_find_row(find_named_datatable("D_Itemable"), iname)
        return row and row.MaxStack
    end))
    if cap ~= nil then
        return cap
    end
    return max_from_itemable_enum(iname)
end

local function static_itemable_name(row)
    local s = dt_find_row(find_named_datatable("D_ItemsStatic"), row)
    if s == nil then
        return nil
    end
    return fname_str(pget(function()
        local h = s.Itemable
        return h and (h.RowName or h)
    end))
end

local function row_max_stack(row)
    row = tostring(row or "")
    if row == "" then
        return nil
    end
    local cached = state.stack_cap[row]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    local names = {}
    local mapped = static_itemable_name(row)
    if mapped and mapped ~= "" then
        table.insert(names, mapped)
    end
    table.insert(names, row)
    if row:sub(1, 5) ~= "Item_" then
        table.insert(names, "Item_" .. row)
    end
    local cap = nil
    for _, n in ipairs(names) do
        cap = itemable_max_from_dt(n)
        if cap ~= nil then
            break
        end
    end
    if cap == nil then
        cap = VANILLA_STACK[row]
    end
    cap = tonumber(cap)
    if cap == nil or cap < 1 then
        state.stack_cap[row] = false
        return nil
    end
    cap = math.floor(cap)
    state.stack_cap[row] = cap
    log("stackcap " .. row .. "=" .. tostring(cap))
    return cap
end

local function is_world_stackable(row)
    local cap = row_max_stack(row)
    return cap ~= nil and cap > 1
end

local function split_stack_amounts(total, cap)
    local out = {}
    total = math.max(0, math.floor(tonumber(total) or 0))
    cap = math.max(1, math.floor(tonumber(cap) or 100))
    while total > 0 do
        local n = total
        if n > cap then
            n = cap
        end
        table.insert(out, n)
        total = total - n
    end
    return out
end

local function collapse_stackable_bag(pdc, bag, src)
    local by_row = {}
    for _, m in ipairs(bag) do
        local row = item_row(m)
        if row and is_world_stackable(row) then
            by_row[row] = by_row[row] or {}
            table.insert(by_row[row], m)
        end
    end
    for row, list in pairs(by_row) do
        local cap = row_max_stack(row)
        local total = 0
        for _, m in ipairs(list) do
            total = total + dyn_stack(m)
        end
        local amounts = split_stack_amounts(total, cap)
        if #list > 1 or (#list == 1 and total > cap) then
            local n_keep = #amounts
            if n_keep > #list then
                n_keep = #list
            end
            local ok = true
            for i = 1, n_keep do
                set_dyn_stack(list[i], amounts[i])
                if not pcall(function()
                    pdc:ClientUpdateMetaItem(list[i])
                end) then
                    ok = false
                end
            end
            if ok then
                for i = n_keep + 1, #list do
                    pcall(function()
                        state.internal_remove = true
                        pdc:ClientRemoveMetaItem(list[i])
                        state.internal_remove = false
                    end)
                    state.internal_remove = false
                end
                log(src .. " collapse " .. tostring(row) .. " cap=" .. tostring(cap) .. " total=" .. tostring(total) .. " piles=" .. tostring(n_keep))
            else
                log(src .. " collapse " .. tostring(row) .. " failed")
            end
        end
    end
end

local function split_over_max(pdc, bag, src)
    for _, m in ipairs(bag) do
        local row = item_row(m)
        local cap = row_max_stack(row)
        local n = dyn_stack(m)
        if cap ~= nil and cap >= 1 and n > cap then
            set_dyn_stack(m, cap)
            pcall(function()
                pdc:ClientUpdateMetaItem(m)
            end)
            local left = n - cap
            local made = 0
            while left > 0 do
                local chunk = left
                if chunk > cap then
                    chunk = cap
                end
                set_dyn_stack(m, chunk)
                pcall(function()
                    m.DatabaseGUID = new_guid()
                end)
                if pcall(function()
                    pdc:ClientAddMetaItem(m)
                end) then
                    made = made + 1
                end
                left = left - chunk
            end
            log(src .. " split " .. tostring(row) .. " x" .. tostring(n) .. " cap=" .. tostring(cap) .. " extra=" .. tostring(made))
        end
    end
end

local function items_in_linked_inv(link_id)
    return items_in_inv(find_inv_by_id(link_id))
end

local function attach_already_copied(att, row)
    state.copied_attach_item = state.copied_attach_item or {}
    local g = item_guid_hex(att)
    if g ~= "" and state.copied_attach_item["g:" .. g] then
        return true
    end
    return state.copied_attach_item["r:" .. tostring(row)] == true
end

local function mark_attach_copied(att, row)
    state.copied_attach_item = state.copied_attach_item or {}
    local g = item_guid_hex(att)
    if g ~= "" then
        state.copied_attach_item["g:" .. g] = true
    end
    state.copied_attach_item["r:" .. tostring(row)] = true
end

local function grant_nested_as_meta(pdc, nested, src, from_inv)
    local n = 0
    for _, att in ipairs(nested or {}) do
        local row = item_row(att)
        -- Attachment bags can also list the parent tool. Never copy that.
        if row and is_attachment_row(row) and not attach_already_copied(att, row) then
            pcall(function()
                att.DatabaseGUID = new_guid()
            end)
            local ok = pcall(function()
                pdc:ClientAddMetaItem(att)
            end)
            log(
                (src or "grant")
                    .. " attachment "
                    .. tostring(row)
                    .. " from inv "
                    .. tostring(from_inv)
                    .. " ok="
                    .. tostring(ok)
            )
            if ok then
                n = n + 1
                mark_attach_copied(att, row)
            end
        end
    end
    return n
end

local function grant_from_inv(pdc, inv, src, label)
    inv = unwrap(inv) or inv
    if pdc == nil or inv == nil then
        return 0
    end
    state.copied_attach_inv = state.copied_attach_inv or {}
    local k = tostring(inv)
    if state.copied_attach_inv[k] then
        return 0
    end
    local n = grant_nested_as_meta(pdc, items_in_inv(inv), src, label)
    if n > 0 then
        state.copied_attach_inv[k] = true
    end
    return n
end

local function attach_items_only(inv)
    local atts, other = {}, 0
    for _, it in ipairs(items_in_inv(inv)) do
        local r = item_row(it)
        if is_attachment_row(r) then
            table.insert(atts, it)
        elseif r and r ~= "" and r ~= "Player_Fists" and r ~= "Player_Fist" then
            other = other + 1
        end
    end
    return atts, other
end

-- Copy nested slot items into YOUR ITEMS, then drop the world inventory id.
-- Station bag does not keep prospect linked inventories (vanilla workshop
-- gear also stores LinkedInventoryId=-1). The module becomes its own stack.
local function grant_linked_attachments(pdc, parent, src)
    local link = dyn_link(parent)
    local row = item_row(parent)
    if is_attachment_row(row) then
        return 0
    end
    log((src or "grant") .. " dyn " .. tostring(row) .. " " .. dyn_props_blob(parent))
    local n = 0
    if link ~= nil and link >= 2 then
        n = n + grant_from_inv(pdc, find_inv_by_id(link), src, link)
    end
    if n == 0 then
        n = n + grant_from_inv(
            pdc,
            pget(function()
                return parent.Inventory or parent.LinkedInventory or parent.ContainerInventory
            end),
            src,
            "item.inv"
        )
    end
    -- One matching one-slot bag only. Never dump every Tool_Attachment inv.
    if n == 0 and link ~= nil and link >= 2 then
        local info = attach_info_for_row(row)
        local tried = {}
        local function consider(inv, label)
            if inv == nil then
                return
            end
            local k = tostring(inv)
            if tried[k] then
                return
            end
            tried[k] = true
            local atts, other = attach_items_only(inv)
            if #atts == 1 and other == 0 then
                n = n + grant_nested_as_meta(pdc, atts, src, label)
            end
        end
        if info then
            for _, inv in ipairs((state.inv_by_info and state.inv_by_info[info]) or {}) do
                if n > 0 then
                    break
                end
                consider(inv, info)
            end
        end
        if n == 0 then
            for _, srow in ipairs(state.scanned_invs or {}) do
                if n > 0 then
                    break
                end
                if srow.attach or is_attach_info(srow.info) then
                    consider(srow.inv, srow.info or "attach")
                end
            end
        end
    end
    if link ~= nil and link >= 2 then
        set_dyn_link(parent, -1)
    end
    if n == 0 and link ~= nil and link >= 2 then
        log(
            (src or "grant")
                .. " linked inv "
                .. tostring(link)
                .. " empty/missing scanned="
                .. attach_scan_blob()
        )
    end
    return n
end

local function stash_cargo_attachments(pdc, src)
    if pdc == nil then
        return 0
    end
    local n = 0
    local seen_p = {}
    for _, it in ipairs(unique_live()) do
        if it.item ~= nil and dyn_has_durability(it.item) and not is_attachment_row(it.row) then
            local pk = item_guid_hex(it.item)
            if pk == "" then
                pk = tostring(it.row) .. "|" .. tostring(it.item)
            end
            if not seen_p[pk] and skip_grant_why(it) == nil then
                seen_p[pk] = true
                n = n + grant_linked_attachments(pdc, it.item, src)
            end
        end
    end
    return n
end

-- Pickaxe already in YOUR ITEMS still points at live prospect inv 50.
-- Rescue that slot before leaving or the module is gone.
local function rescue_bag_links(pdc, bag, src)
    if pdc == nil or bag == nil then
        return 0
    end
    local n = 0
    state.rescue_miss = state.rescue_miss or {}
    for _, item in ipairs(bag) do
        local link = dyn_link(item)
        if link ~= nil and link >= 2 and not state.rescue_miss[link] then
            local nested = items_in_linked_inv(link)
            local copied = grant_nested_as_meta(pdc, nested, src or "rescue", link)
            -- Station cannot keep prospect slot ids. A leftover id shows a
            -- ghost module on the tool that cannot be pulled off.
            set_dyn_link(item, -1)
            pcall(function()
                pdc:ClientUpdateMetaItem(item)
            end)
            n = n + copied
            if copied > 0 or find_inv_by_id(link) ~= nil then
                log(
                    (src or "rescue")
                        .. " unlink "
                        .. tostring(item_row(item))
                        .. " was "
                        .. tostring(link)
                        .. " copied="
                        .. tostring(copied)
                )
            else
                state.rescue_miss[link] = true
                log(
                    (src or "rescue")
                        .. " cleared dead link "
                        .. tostring(link)
                        .. " on "
                        .. tostring(item_row(item))
                )
            end
        end
    end
    return n
end

local function spoil_time_for(row)
    row = tostring(row or "")
    local n = tonumber(catalog_get(CATALOG.spoil_time or {}, row))
        or tonumber(catalog_get(FALLBACK_SPOIL_TIME, row))
    if n ~= nil and n > 0 then
        return math.floor(n)
    end
    return nil
end

local function fridge_bag(pdc, bag, src)
    if pdc == nil or bag == nil then
        return 0
    end
    local n = 0
    for _, item in ipairs(bag) do
        local row = item_row(item)
        local max_spoil = spoil_time_for(row)
        local cur = dyn_spoil(item)
        if max_spoil ~= nil then
            local stale = cur == nil or cur < max_spoil
            if stale then
                set_dyn_named(item, SPOIL_PROP, max_spoil)
                set_dyn_named(item, "Decayable_CurrentSpoilTime", max_spoil)
                local ok, err = pcall(function()
                    pdc:ClientUpdateMetaItem(item)
                end)
                if ok then
                    n = n + 1
                    log((src or "fridge") .. " " .. tostring(row) .. " spoil " .. tostring(cur) .. " -> " .. tostring(max_spoil))
                else
                    log((src or "fridge") .. " " .. tostring(row) .. " update fail " .. tostring(err))
                end
            end
        end
    end
    return n
end

local function current_pc()
    return pget(function()
        return FindFirstOf("BP_IcarusPlayerControllerSpace_C")
    end) or pget(function()
        return FindFirstOf("BP_IcarusPlayerControllerSurvival_C")
    end) or pget(function()
        return FindFirstOf("IcarusPlayerControllerSurvival")
    end) or pget(function()
        return FindFirstOf("PlayerController")
    end)
end

local function note_overflow_inv(it)
    if not is_overflow_cargo(it) then
        return
    end
    if it.inv_obj ~= nil then
        table.insert(state.granted_overflow_invs, it.inv_obj)
    end
    if it.actor ~= nil and state.spawned_overflow == nil then
        state.spawned_overflow = it.actor
    end
end

local function try_stamp_and_add(src)
    src = src or "grant"
    if not cfg.enabled then
        log(src .. " disabled")
        return
    end
    math.randomseed(os.time() % 2147483647)
    snapshot_cargo()
    local attach_blob = attach_scan_blob()
    if attach_blob ~= "" then
        log(src .. " attach invs " .. attach_blob)
    end
    local payload = {
        phase = "stamp_and_add",
        src = src,
        closest = state.closest_ship,
        live_n = #(state.live or {}),
        added = {},
        skipped = {},
    }
    write_grant(payload)
    log(src .. " closest=" .. tostring(state.closest_ship or "none"))
    local pc = pget(function()
        return FindFirstOf("BP_IcarusPlayerControllerSurvival_C")
    end) or pget(function()
        return FindFirstOf("IcarusPlayerControllerSurvival")
    end) or pget(function()
        return FindFirstOf("PlayerController")
    end)
    local pdc, bag = pick_pdc_and_bag(pc)
    payload.pc = ufull(pc)
    payload.pdc = pdc and ufull(pdc) or nil
    if pdc == nil then
        payload.phase = "no_pdc"
        payload.err = "PlayerDataComponent missing"
        write_grant(payload)
        log(src .. " no PlayerDataComponent")
        return
    end
    payload.bag_n = #(bag or {})
    log(src .. " bag=" .. tostring(payload.bag_n) .. " live=" .. tostring(#(state.live or {})))
    if payload.bag_n > 0 then
        fridge_bag(pdc, bag, src)
        rescue_bag_links(pdc, bag, src)
        collapse_stackable_bag(pdc, bag, src)
        bag = meta_bag_items(pdc)
        split_over_max(pdc, bag, src)
        bag = meta_bag_items(pdc)
        payload.bag_n = #bag
    end
    state.granted = state.granted or {}
    state.granted_overflow_invs = {}
    local seen = {}
    for _, it in ipairs(unique_live()) do
        local key = tostring(it.item)
        local gkey = stack_key(it)
        if seen[key] or seen[gkey] then
            table.insert(payload.skipped, { row = it.row, inv = it.inv, why = "dup" })
        else
            seen[key] = true
            local why = skip_grant_why(it)
            if why then
                if why ~= "not_ship_cargo" and why ~= "other_overflow" and why ~= "other_ship" then
                    seen[gkey] = true
                end
                table.insert(payload.skipped, {
                    row = it.row,
                    inv = it.inv,
                    ship = it.ship,
                    owner = it.owner,
                    stack = it.stack,
                    why = why,
                })
                if why ~= "blocked" and why ~= "nested_attach" then
                    log(src .. " skip " .. tostring(it.row) .. " x" .. tostring(it.stack) .. " " .. why)
                end
            else
                seen[gkey] = true
                local where = "pod"
                if it.ship and it.ship == state.closest_ship then
                    where = "your pod"
                elseif it.ship then
                    where = "other pod"
                end
                local live_guid = item_guid_hex(it.item)
                if live_guid == "" then
                    live_guid = it.guid or ""
                end
                local durable = dyn_has_durability(it.item)
                if durable then
                    local in_bag = false
                    if live_guid ~= "" then
                        for _, m in ipairs(bag) do
                            if item_guid_hex(m) == live_guid then
                                in_bag = true
                                break
                            end
                        end
                    end
                    if in_bag then
                        table.insert(payload.skipped, { row = it.row, why = "already_in_bag" })
                        log(src .. " skip " .. tostring(it.row) .. " already in YOUR ITEMS")
                    else
                        local guid = new_guid()
                        pcall(function()
                            it.item.DatabaseGUID = guid
                        end)
                        local ok, err = pcall(function()
                            pdc:ClientAddMetaItem(it.item)
                        end)
                        table.insert(payload.added, {
                            row = it.row,
                            stack = it.stack,
                            guid = guid,
                            ok = ok == true,
                            err = ok and nil or tostring(err),
                            how = "add",
                        })
                        log(
                            src
                                .. " add "
                                .. tostring(it.row)
                                .. " x"
                                .. tostring(it.stack)
                                .. " from "
                                .. where
                                .. " inv="
                                .. tostring(it.inv)
                                .. " tag="
                                .. tostring(it.tag)
                                .. " ok="
                                .. tostring(ok)
                        )
                        if ok then
                            note_overflow_inv(it)
                        end
                    end
                elseif state.granted[gkey] then
                    table.insert(payload.skipped, { row = it.row, why = "already_granted" })
                    log(src .. " skip " .. tostring(it.row) .. " x" .. tostring(it.stack) .. " already granted")
                else
                    local matches = {}
                    for _, m in ipairs(bag) do
                        if item_row(m) == it.row and is_world_stackable(it.row) then
                            table.insert(matches, m)
                        end
                    end
                    local add_n = tonumber(it.stack) or 1
                    if #matches == 0 then
                        local guid = new_guid()
                        pcall(function()
                            it.item.DatabaseGUID = guid
                        end)
                        local ok, err = pcall(function()
                            pdc:ClientAddMetaItem(it.item)
                        end)
                        if ok then
                            state.granted[gkey] = true
                            table.insert(bag, it.item)
                        end
                        table.insert(payload.added, {
                            row = it.row,
                            stack = add_n,
                            guid = guid,
                            ok = ok == true,
                            err = ok and nil or tostring(err),
                            how = "add",
                        })
                        log(src .. " add " .. tostring(it.row) .. " x" .. tostring(add_n) .. " from " .. where .. " ok=" .. tostring(ok))
                        if ok then
                            note_overflow_inv(it)
                        end
                    else
                        local cap = row_max_stack(it.row)
                        local total = add_n
                        for _, m in ipairs(matches) do
                            total = total + dyn_stack(m)
                        end
                        local amounts = split_stack_amounts(total, cap)
                        local ok, err = true, nil
                        local n_keep = #amounts
                        if n_keep > #matches then
                            n_keep = #matches
                        end
                        for i = 1, n_keep do
                            set_dyn_stack(matches[i], amounts[i])
                            local uok, uerr = pcall(function()
                                pdc:ClientUpdateMetaItem(matches[i])
                            end)
                            if not uok then
                                ok, err = false, uerr
                            end
                        end
                        if ok then
                            for i = n_keep + 1, #matches do
                                pcall(function()
                                    state.internal_remove = true
                                    pdc:ClientRemoveMetaItem(matches[i])
                                    state.internal_remove = false
                                end)
                                state.internal_remove = false
                            end
                            local tg = item_guid_hex(matches[1])
                            if tg ~= "" then
                                pcall(function()
                                    it.item.DatabaseGUID = tg
                                end)
                            end
                            for i = n_keep + 1, #amounts do
                                local guid = new_guid()
                                pcall(function()
                                    it.item.DatabaseGUID = guid
                                end)
                                set_dyn_stack(it.item, amounts[i])
                                local aok, aerr = pcall(function()
                                    pdc:ClientAddMetaItem(it.item)
                                end)
                                if not aok then
                                    ok, err = false, aerr
                                end
                            end
                            state.granted[gkey] = true
                            log(src .. " merge " .. tostring(it.row) .. " +" .. tostring(add_n) .. " total=" .. tostring(total) .. " cap=" .. tostring(cap) .. " piles=" .. tostring(#amounts))
                            note_overflow_inv(it)
                        else
                            log(src .. " merge " .. tostring(it.row) .. " failed: " .. tostring(err))
                        end
                        table.insert(payload.added, {
                            row = it.row,
                            stack = add_n,
                            now = total,
                            cap = cap,
                            piles = #amounts,
                            ok = ok == true,
                            err = ok and nil or tostring(err),
                            how = "merge",
                        })
                    end
                end
            end
        end
    end
    payload.phase = "stamp_and_add_done"
    payload.n = #(payload.added)
    write_grant(payload)
    log(src .. " added " .. tostring(payload.n) .. " stacks")
    return payload.n
end

local function empty_one_overflow_bag(bag, src)
    bag = unwrap(bag) or bag
    local seen = {}
    local ntry = 0
    local function try_empty(inv, label)
        inv = unwrap(inv) or inv
        if inv == nil then
            return
        end
        local k = tostring(inv)
        if seen[k] then
            return
        end
        seen[k] = true
        ntry = ntry + 1
        local info = inv_info_name(inv) or ""
        local n = pget(function()
            return inv:GetNumItems()
        end)
        local ok, err = pcall(function()
            inv:RemoveAllItems()
        end)
        log(
            (src or "empty")
                .. " RemoveAllItems "
                .. tostring(label)
                .. " info="
                .. tostring(info)
                .. " n="
                .. tostring(n)
                .. " ok="
                .. tostring(ok)
                .. " err="
                .. tostring(err)
        )
    end
    for _, inv in ipairs(state.granted_overflow_invs or {}) do
        try_empty(inv, "granted")
    end
    if bag ~= nil then
        pcall(function()
            if bag.GetAllInventories then
                arr_each(bag:GetAllInventories(true), function(_, inv)
                    try_empty(inv, "GetAllInventories")
                end)
            end
        end)
        local c = pget(function()
            return bag.Inventory or bag.InventoryComponent
        end)
        pcall(function()
            arr_each(c and (c.Inventories or c.InventoryList), function(_, inv)
                try_empty(inv, "Inventories")
            end)
        end)
        pcall(function()
            if c and c.GetInventories then
                arr_each(c:GetInventories(), function(_, inv)
                    try_empty(inv, "GetInventories")
                end)
            end
        end)
        pcall(function()
            if c and c.GetInventory then
                try_empty(c:GetInventory("Overflow_Bag"), "Overflow_Bag")
            end
        end)
    end
    if ntry == 0 then
        log((src or "empty") .. " no overflow inventories to empty bag=" .. tostring(bag ~= nil))
    end
end

local function restore_game_input()
    local pc = pget(function()
        return FindFirstOf("BP_IcarusPlayerControllerSurvival_C")
    end) or current_pc()
    if pc == nil then
        log("restore input no pc")
        return
    end
    local ok_cur = pcall(function()
        pc.bShowMouseCursor = false
    end)
    local ok_mode = pcall(function()
        pc:SetInputMode_GameOnly()
    end)
    log("restore input cursor=" .. tostring(ok_cur) .. " gameonly=" .. tostring(ok_mode))
end

local function hide_overflow_confirm(quiet)
    local found = pget(function()
        return FindAllOf("UMG_ConfirmationPopup_C")
    end)
    if found ~= nil and type(found) ~= "table" then
        found = { found }
    end
    local n = 0
    for _, w in ipairs(found or {}) do
        w = unwrap(w) or w
        local vis = pget(function()
            return w.Visibility
        end)
        local name = ufull(w) or ""
        if vis == 0
            and name:find("UMG_UserInterface_C", 1, true)
            and not name:find("TitleScreen", 1, true)
            and not name:find("UserInterfaceSpace", 1, true)
        then
            local how = "vis"
            if pcall(function()
                w:OptionAClicked()
            end) then
                how = "OptionAClicked"
            elseif pcall(function()
                w:OnOptionA()
            end) then
                how = "OnOptionA"
            elseif pcall(function()
                w:OnConfirm()
            end) then
                how = "OnConfirm"
            end
            pcall(function()
                w:SetVisibility(1)
            end)
            restore_game_input()
            log("hide confirm how=" .. how .. " " .. name)
            n = n + 1
        end
    end
    if n == 0 and not quiet then
        log("hide confirm none visible")
    end
    return n > 0
end

local function watch_overflow_confirm()
    if state.watching_confirm then
        return
    end
    state.watching_confirm = true
    local t0 = os.clock()
    pcall(function()
        LoopAsync(50, function()
            local hid = false
            pcall(function()
                hid = hide_overflow_confirm(true) == true
            end)
            if hid or (os.clock() - t0) > 3 then
                state.watching_confirm = false
                return true
            end
            return false
        end)
    end)
end

parse_ini()
load_catalog()
math.randomseed(os.time() % 2147483647)

local function grant_pod(src, force)
    if on_station() then
        return
    end
    if state.granting then
        return
    end
    local now = os.clock()
    if not force and state.last_grant_clock and (now - state.last_grant_clock) < 2 then
        return
    end
    state.granting = true
    state.last_grant_clock = now
    log(src .. " grant cargo")
    local ok, added = pcall(try_stamp_and_add, src)
    state.granting = false
    if src:find("overflow", 1, true) then
        state.overflow_done = true
        if ok and tonumber(added) and tonumber(added) > 0 then
            local bag = state.spawned_overflow
            if bag == nil then
                local list = state.last_overflow_actors or {}
                if #list == 1 then
                    bag = list[1]
                    log(src .. " empty fallback single overflow bag")
                else
                    log(src .. " skip empty, overflow bags=" .. tostring(#list))
                end
            end
            empty_one_overflow_bag(bag, src)
            hide_overflow_confirm()
            restore_game_input()
        end
    end
    if not ok then
        log(src .. " grant error: " .. tostring(added))
    end
end

local function try_hook(path, src)
    -- Pre: copy nested attachments while pod/player still hold them.
    -- Post still grants overflow cargo. Do not inspect hook args.
    state.hooked = state.hooked or {}
    if state.hooked[path] then
        return true
    end
    local function stash_pre()
    end
    local ok, err = pcall(function()
        RegisterHook(path, function()
            stash_pre()
        end, function()
            grant_pod(src .. "_post", true)
        end)
    end)
    if not ok then
        ok, err = pcall(function()
            RegisterHook(path, function()
                stash_pre()
                grant_pod(src)
            end)
        end)
    end
    if ok then
        state.hooked[path] = true
        log("hook " .. path)
    elseif path:find("/Script/", 1, true) then
        log("hook fail " .. path)
    end
    return ok == true
end

local HOOKS = {
    { "/Script/Icarus.IcarusGameModeSurvival:CreateAndFillOverflowBag", "overflow" },
    { "/Script/Icarus.IcarusGameModeSurvival:SpawnOverflowForReturnedItems", "overflow" },
    { "/Game/BP/Systems/BP_IcarusGameMode.BP_IcarusGameMode_C:CreateAndFillOverflowBag", "overflow" },
    { "/Game/BP/Systems/BP_IcarusGameMode.BP_IcarusGameMode_C:SpawnOverflowForReturnedItems", "overflow" },
    { "/Game/BP/Player/BP_IcarusPlayerControllerSurvival.BP_IcarusPlayerControllerSurvival_C:CreateOverflowBag", "overflow" },
}

for _, h in ipairs(HOOKS) do
    try_hook(h[1], h[2])
end

pcall(function()
    LoopAsync(3000, function()
        for _, h in ipairs(HOOKS) do
            try_hook(h[1], h[2])
        end
        return true
    end)
end)

pcall(function()
    local function on_overflow_spawn(bag)
        bag = unwrap(bag) or bag
        local name = ufull(bag) or tostring(bag)
        if state.spawned_overflow_name == name then
            return
        end
        state.spawned_overflow = bag
        state.spawned_overflow_name = name
        state.copied_attach_item = {}
        state.copied_attach_inv = {}
        log("overflow spawn " .. tostring(name))
        watch_overflow_confirm()
        local t0 = os.clock()
        pcall(function()
            LoopAsync(100, function()
                if (os.clock() - t0) < 0.4 then
                    return false
                end
                grant_pod("overflow_spawn", true)
                return true
            end)
        end)
    end
    NotifyOnNewObject(
        "/Game/BP/Objects/World/Items/Deployables/Containers/BP_Overflow_Bag.BP_Overflow_Bag_C",
        on_overflow_spawn
    )
    NotifyOnNewObject(
        "/Game/BP/Objects/World/Items/Deployables/Containers/BP_Overflow_Bag_NoPhysics.BP_Overflow_Bag_NoPhysics_C",
        on_overflow_spawn
    )
    log("watch BP_Overflow_Bag spawn")
end)
