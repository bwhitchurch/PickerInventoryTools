local Event = require('__stdlib__/stdlib/event/event')
local Inventory = require('__stdlib__/stdlib/entity/inventory')

local chest_types = {
    ['container'] = true,
    ['logistic-container'] = true,
    ['cargo-wagon'] = true
}

function Inventory.transfer_inventory(source, destination)
    local filtered = source.is_filtered()
    local destination_filterable = destination.supports_filters()
    local source_count = #source
    for i = 1, #destination do
        if i <= source_count then
            destination[i].transfer_stack(source[i])
            if filtered and destination_filterable then
                destination.set_filter(i, source.get_filter(i))
            end
        else
            break
        end
    end
end

local function move_to_container(event)
    local stack = event.stack
    if stack and stack.name:find('^picker%-moveable%-') then
        local chest = event.created_entity
        local source = event.stack.get_inventory(defines.inventory.item_main)
        local destination = chest.get_inventory(defines.inventory.chest)

        Inventory.transfer_inventory(source, destination)
        local data = global.inventory_chest[stack.item_number]
        if data then
            if data.bar then
                destination.set_bar(data.bar)
            end
            local proto = chest.prototype
            if proto.logistic_mode == 'storage' then
                chest.storage_filter = data.storage_filter
            elseif proto.logistic_mode == 'requester' or proto.logistic_mode == 'buffer' then
                for slot, filter in pairs(data.request_slots or {}) do
                    chest.set_request_slot(filter, slot)
                end
                chest.request_from_buffers = data.request_from_buffers
            end
        end
        global.inventory_chest[stack.item_number] = nil
        __DebugAdapter.print('test')
    end
end

-- Move the contents from the chest into an item in our inventory
local function move_to_inventory(event)
    local chest = event.entity
    local item_name = 'picker-moveable-' .. chest.name
    if chest_types[chest.type] and game.item_prototypes[item_name] then
        if chest.has_items_inside() then
            local player = game.get_player(event.player_index)
            local p_inv = player.get_main_inventory()

            -- Is there an empty inventory spot?
            if p_inv.can_insert(item_name) then
                -- Create an item-with-inventory in an available slot
                local stack
                for i = 1, #p_inv do
                    if not p_inv[i].valid_for_read then
                        stack = p_inv[i]
                        break
                    end
                end
                -- Should have stack since we can insert but check anyway.
                if stack and stack.set_stack(item_name) then
                    stack.health = chest.get_health_ratio()
                    local proto = chest.prototype

                    local source = chest.get_inventory(defines.inventory.chest)
                    local dest = stack.get_inventory(defines.inventory.item_main)
                    Inventory.transfer_inventory(source, dest)

                    global.inventory_chest = global.inventory_chest or {}
                    global.inventory_chest[stack.item_number] = {}
                    local data = global.inventory_chest[stack.item_number]

                    data.bar = source.supports_bar() and source.get_bar()
                    data.storage_filter = proto.logistic_mode == 'storage' and chest.storage_filter
                    local requester = proto.logistic_mode == 'requester' or proto.logistic_mode == 'buffer'
                    if requester then
                        data.request_slots = {}
                        for i = 1, chest.request_slot_count do
                            data.request_slots[i] = chest.get_request_slot(i)
                        end
                        data.request_from_buffers = chest.request_from_buffers
                    end
                    __DebugAdapter.print('test')
                    chest.destroy()
                end
            end
        end
    end
end

if settings.startup['picker-moveable-chests'].value then
    Event.on_event(defines.events.on_built_entity, move_to_container)
    Event.on_event(defines.events.on_pre_player_mined_item, move_to_inventory)
end