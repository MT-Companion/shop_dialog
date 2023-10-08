-- shop_dialog/init.lua
-- Formspec-based shop dialog
--[[
    Copyright (C) 2023  1F616EMO

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
    USA
]]

shop_dialog = {}
local S = minetest.get_translator("shop_dialog")

-- The maximum number of items to be brought at once
shop_dialog.MAX_ITEM_NUMBER = 100

-- Log in the format of "[shop_dialog] <msg>"
local function log(lvl,msg)
    return minetest.log(lvl,"[shop_dialog] " .. msg)
end

-- Assert a type of a object
local function assert_type(obj,typ,err)
    assert(type(obj) == typ, "[shop_dialog] " .. err)
end

-- Format error message
local function err(msg)
    error("[shop_dialog] " .. msg,2)
end

-- Dummy functions as default values
shop_dialog.func_return_max   = function() return shop_dialog.MAX_ITEM_NUMBER end
shop_dialog.func_return_zero  = function() return 0 end
shop_dialog.func_return_true  = function() return true end
shop_dialog.func_return_false = function() return false end

-- Verify ShopDialogEntry
shop_dialog.verify_ShopDialogEntry = function(obj)
    ---@diagnostic disable-next-line: undefined-field
    obj = table.copy(obj)
    assert_type(obj, "table", "ShopDialogEntry must be a table.")
    if not(obj.item and obj.item.get_short_description) then
        err("ShopDialogEntry.item must be an ItemStack.")
    end
    assert_type(obj.cost,"number","ShopDialogEntry.cost must be a number.")
    if obj.max_amount == nil then
        obj.max_amount = shop_dialog.func_return_max
    else
        assert_type(obj.max_amount,"function","ShopDialogEntry.max_amount must be a function.")
    end
    if obj.after_buy ~= nil then
        assert_type(obj.after_buy,"function","ShopDialogEntry.after_buy must be either function or nil.")
    end
    return obj
end

-- Verify ShopDialog
shop_dialog.verify_ShopDialog = function(obj)
    ---@diagnostic disable-next-line: undefined-field
    obj = table.copy(obj)
    assert_type(obj, "table", "ShopDialog must be a table.")
    for _,n in ipairs({"title","footnote"}) do
        local t = type(obj[n])
        if t ~= "string" and t ~= "function" then
            err("ShopDialogEntry." .. n .. " must be either function or string.")
        end
    end
    if obj.after_buy ~= nil then
        assert_type(obj.after_buy,"function","ShopDialog.after_buy must be either function or nil.")
    end
    assert_type(obj.entries,"table","ShopDialog.entries must be a table")
    for k,v in ipairs(obj.entries) do
        obj.entries[k] = shop_dialog.verify_ShopDialogEntry(v)
    end
    return obj
end

-- Register ShopDialog
shop_dialog.registered_dialogs = {}
shop_dialog.register_dialog = function(name,obj)
    obj = shop_dialog.verify_ShopDialog(obj)
    shop_dialog.registered_dialogs[name] = obj
end

-- Get amount
shop_dialog.get_max_amount = function(name, ShopDialogEntry)
    local amount_from_entry, msg = ShopDialogEntry.max_amount(name)
    if amount_from_entry <= 0 then return 0, msg end
    local amount_from_func = math.min(amount_from_entry,shop_dialog.MAX_ITEM_NUMBER)
    if amount_from_func <= 0 then return 0, "UNKNOWN" end
    local acc_balance = unified_money.get_balance_safe(name)
    if acc_balance < ShopDialogEntry.cost then return 0, "MONEY" end

    local player = minetest.get_player_by_name(name)
    if not player then return 0 end
    local inv = player:get_inventory()
    for i = 1, amount_from_func, 1 do
        local cost = ShopDialogEntry.cost * i
        if cost > acc_balance then return i - 1, "MONEY" end
        local item = ItemStack(ShopDialogEntry.item)
        item:set_count(item:get_count() * i)
        if not inv:room_for_item("main",item) then
            return i - 1, "ROOM_ITEM"
        end
    end
    return amount_from_func, "ROOM_ITEM"
end

-- Actualy buy the item
shop_dialog.buy = function(name, ShopDialogEntry, amount)
    if amount <= 0 then return true end
    local max_amount, msg = shop_dialog.get_max_amount(name, ShopDialogEntry)
    if max_amount < amount then
        return false, msg
    end
    local player = minetest.get_player_by_name(name)
    local inv = player:get_inventory()

    local stack = ItemStack(ShopDialogEntry.item)
    -- Guarenteed space from get_max_amount
    unified_money.del_balance_safe(name,ShopDialogEntry.cost * amount)
    for _ = 1, amount, 1 do
        inv:add_item("main", stack)
    end
    log("action", "Player " .. name .. " brought " .. stack:to_string())
    return true
end

local function handle_select_btn(i)
    ---@diagnostic disable-next-line: unused-local
    return function(_, ctx)
        ctx.curr_select = i
        return true
    end
end

local errmsg_to_str = {
    UNKNOWN = S("Unknown error."),
    ROOM_ITEM = S("No room for items."),
    MONEY = S("Not enough balance in your account.")
}

local function handle_buy_btn(curr_dialog, curr_select)
    local curr_entry = curr_dialog.entries[curr_select]
    return function(player, ctx)
        local name = player:get_player_name()
        local count = tonumber(ctx.form.count)
        if not count then
            ctx.msg = S("Invalid amount.")
            return true
        end
        local stat, msg = shop_dialog.buy(name,curr_entry,count)
        if curr_entry.after_buy then
            curr_entry.after_buy(name, count)
        end
        if curr_dialog.after_buy then
            curr_dialog.after_buy(name, count)
        end
        if not stat then
            ctx.msg = errmsg_to_str[msg] or msg
        else
            ctx.msg = S("Successfully brought item.")
            return true
        end
    end
end

local function get_short_description(item)
    local short_desc = item:get_short_description()
    local count = item:get_count()
    if count > 1 then
        return short_desc .. " x" .. tostring(count)
    else
        return short_desc
    end
end

-- Register GUI
local gui = flow.widgets
shop_dialog.flow_gui = flow.make_gui(function(player, ctx)
    assert_type(ctx.dialog_id,"string","[shop_dialog] ctx.dialog_id in shop_dialog.flow_gui must be string")
    local current_dialog = shop_dialog.registered_dialogs[ctx.dialog_id]
    assert(current_dialog ~= nil, "[shop_dialog] Dialog specified in ctx.dialog_id does not exist")
    local name = player:get_player_name()

    if ctx.curr_select == nil then
        ctx.curr_select = 1
    end

    local curr_max_amount = 0
    local curr_max_msg = nil

    -- Left: Shop list buttons (ScrollableVBox)
    local shop_list_gui = {name="svb_list"}
    for i,entry in ipairs(current_dialog.entries) do
        local itemname = entry.item:get_name()
        local entry_btn_gui = {min_w = 15, h = 1.4} -- Stack
        local max_amount, raw_msg = shop_dialog.get_max_amount(name, entry)
        local msg = nil
        if raw_msg then
            msg = errmsg_to_str[raw_msg] or raw_msg
        end
        if i == ctx.curr_select then
            curr_max_amount = max_amount
            curr_max_msg = msg ~= "" and msg or nil
        end
        table.insert(entry_btn_gui, gui.Button {
            on_event = handle_select_btn(i), label = "",
        })
        table.insert(entry_btn_gui, gui.Label {
            padding = 1.4, align_h = "left",
            label = get_short_description(entry.item) .. "\n$" .. tostring(entry.cost)
        })
        table.insert(entry_btn_gui, gui.ItemImage {
            w = 1, h = 1,
            item_name = itemname,
            padding = 0.2, align_h = "left"
        })
        table.insert(entry_btn_gui, gui.Label {
            align_h = "right", align_v = "top", padding = 0.2, expand = true,
            label = (max_amount <= 0 and ((msg ~= "" and msg) or S("Sold out")) or S("Purchase up to @1",max_amount))
        })

        -- Add it into the list
        table.insert(shop_list_gui,gui.Stack(entry_btn_gui))
    end

    -- Right: Details & Buy (VBox)
    local shop_details_gui = {min_w = 10}
    do
        local entry = current_dialog.entries[ctx.curr_select]
        if not entry then
            table.insert(shop_details_gui, gui.Label {
                label = S("Invalid item.")
            })
        else
            local itemname = entry.item:get_name()
            table.insert(shop_details_gui, gui.Label {
                align_h = "center",
                label = get_short_description(entry.item)
            })
            table.insert(shop_details_gui, gui.ItemImage {
                w = 5, h = 5, align_h = "center",
                item_name = itemname,
            })
            table.insert(shop_details_gui, gui.Spacer {})
            if curr_max_amount <= 0 then
                table.insert(shop_details_gui, gui.Label {
                    align_h = "center",
                    label = curr_max_msg or S("Sold out")
                })
            else
                local details_buy_gui = {} -- HBox
                do
                    table.insert(details_buy_gui, gui.Button {
                        w = 0.7, h = 0.7, align_h = "right", expand = true,
                        label = "-",
                        on_event = function(_, ctx) -- luacheck: ignore 432
                            if not tonumber(ctx.form.count) then
                                ctx.form.count = 1
                            end
                            if tonumber(ctx.form.count) > 1 then
                                ctx.form.count = tostring(tonumber(ctx.form.count) - 1)
                                return true
                            end
                        end
                    })
                    table.insert(details_buy_gui, gui.Field {
                        name = "count", align_h = "center", w = 3,
                        default = "1",
                    })
                    table.insert(details_buy_gui, gui.Button {
                        w = 0.7, h = 0.7, align_h = "left", expand = true,
                        label = "+",
                        on_event = function(_, ctx) -- luacheck: ignore 432
                            if not tonumber(ctx.form.count) then
                                ctx.form.count = 1
                            end
                            if tonumber(ctx.form.count) < curr_max_amount then
                                ctx.form.count = tostring(tonumber(ctx.form.count) + 1)
                                return true
                            end
                        end
                    })
                end
                table.insert(shop_details_gui, gui.HBox(details_buy_gui))
                table.insert(shop_details_gui, gui.Button {
                    align_h = "center",
                    label = S("Buy"),
                    on_event = handle_buy_btn(current_dialog, ctx.curr_select)
                })
            end
        end
    end

    local title = current_dialog.title
    if type(title) == "function" then
        title = title(name)
    end
    if title == nil or title == "" then
        title = S("Shop dialog")
    end

    local footnote = current_dialog.foornote
    if type(footnote) == "function" then
        footnote = footnote(name)
    end
    if footnote == "" then
        footnote = nil
    end

    return gui.VBox {
        -- Title
        gui.HBox {
            gui.Label {
                label = title
            },
            gui.Label {
                align_h = "right", expand = true,
                label = um_translate_common.balance_show(unified_money.get_balance_safe(name))
            },
            gui.ButtonExit {
                h = 0.5, w = 0.5,
                label = "x"
            }
        },
        -- hr
        gui.Box{w = 1, h = 0.05, color = "grey", padding = 0},
        -- Body
        gui.HBox {
            h = 17,
            gui.ScrollableVBox(shop_list_gui),
            gui.Vbox(shop_details_gui)
        },
        -- hr
        gui.Box{w = 1, h = 0.05, color = "grey", padding = 0},
        -- bottom
        gui.Label { -- status msg
            label = ctx.msg or S("Ready")
        },
        footnote and gui.Label { -- footnote
            label = footnote,
        } or gui.Nil{}
    }
end)

shop_dialog.show_to = function(name,dialog_id)
    assert(shop_dialog.registered_dialogs[dialog_id] ~= nil,
        "[shop_dialog] Attempt to open non-existing dialog " .. dialog_id)
    local player = minetest.get_player_by_name(name)
    assert(player ~= nil, "[shop_dialog] Attempt to open dialog " .. dialog_id .. " to non-existing player " .. name)
    shop_dialog.flow_gui:show(player,{dialog_id=dialog_id})
end

-- Examples
shop_dialog.register_dialog("shop_dialog:example", {
    -- The title to be shown on top of the shops
    -- Can be either string or function.
    title = "Dave Null's Shop",

    -- The footnote to be shown under the shops
    -- Can be either string or function.
    footnote = "Hello World!",

    entries = {
        {
            -- The item to be given
            item = ItemStack("air 10"),

            -- Money to buy the item.
            -- This uses the Unified Money system.
            cost = 10,

            -- Function returning the maximum allowed number of items to be brought.
            -- This cannot exceed 100, and if exceed, it will fallback to 100.
            -- If 0, the second returned value can be a string explaining the reason.
            -- Default to a dummy function that returns 100.
            max_amount = function(name) return 100 end, -- luacheck: ignore 212
        },
        {
            item = ItemStack("mapgen_stone"),
            cost = 50,
            max_amount = function(name) return 200 end, -- luacheck: ignore 212 -- should become 100
        },
        {
            -- The item to be given
            item = ItemStack("ignore 10"),

            -- Money to buy the item.
            -- This uses the Unified Money system.
            cost = 10,

            -- Function returning the maximum allowed number of items to be brought.
            -- This cannot exceed 100, and if exceed, it will fallback to 100.
            -- If 0, the second returned value can be a string explaining the reason.
            -- Default to a dummy function that returns 100.
            max_amount = function(name) return 0 end, -- luacheck: ignore 212
        },
    }
})

minetest.register_chatcommand("shop_dialog_example",{
    privs = {server=true},
    description = S("Shop dialog examples"),
    func = function(name, _)
        shop_dialog.show_to(name,"shop_dialog:example")
        return true, S("Dialog shown.")
    end
})


