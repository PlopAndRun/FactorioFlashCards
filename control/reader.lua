local persistence = require 'persistence'
local memorycard = require 'control.memorycard'
local utils = require 'utils'
local names = utils.names
local tag_names = utils.tags.reader
local gui = require 'control.reader_gui'
local _M = {}

local function find_chest(entity)
    return entity.surface.find_entity(names.reader.CONTAINER, entity.position)
end

local function connect(entity, wire, target)
    local connector = entity.get_wire_connector(wire, true)
    connector.connect_to(target.get_wire_connector(wire, true), false)
end

local function disconnect(entity, wire, target)
    local connector = entity.get_wire_connector(wire, true)
    connector.disconnect_from(target.get_wire_connector(wire, true))
end

local function create_cells_for_channel(cells, holder, data, connect_red, connect_green)
    local surface = holder.reader.surface
    local cell = surface.create_entity {
        name = names.reader.SIGNAL_SENDER_CELL,
        position = {
            x = holder.sender.position.x,
            y = holder.sender.position.y,
        },
        force = holder.sender.force,
        create_build_effect_smoke = false,

    }
    table.insert(cells, cell)

    if connect_red then
        connect(holder.sender, defines.wire_connector_id.circuit_red, cell);
    end
    if connect_green then
        connect(holder.sender, defines.wire_connector_id.circuit_green, cell);
    end

    local cb = cell.get_or_create_control_behavior()
    local section = cb.get_section(1)
    local filters = {}
    for i, value in pairs(data) do
        filters[i] = {
            value = {
                type = value.signal.type or 'item',
                name = value.signal.name,
                quality = value.signal.quality or 'normal',
                comparator = '=',
            },
            min = value.count,
        }
    end
    section.filters = filters
end

local function create_cells(holder, card)
    local data = memorycard.read_data(card)
    local cells = {}
    if #data.combined > 0 then
        create_cells_for_channel(cells, holder, data.combined, true, true)
    end
    if #data.red > 0 then
        create_cells_for_channel(cells, holder, data.red, true, false)
    end
    if #data.green > 0 then
        create_cells_for_channel(cells, holder, data.green, false, true)
    end
    holder.cells = cells
end

local function destroy_cells(holder)
    for _, cell in pairs(holder.cells) do
        cell.destroy()
    end
    holder.cells = nil
end

function _M.apply_options(holder)
    local channel = holder.options.diagnostics_channel
    local red = channel == persistence.CHANNEL_OPTION.RED or channel == persistence.CHANNEL_OPTION.BOTH
    local green = channel == persistence.CHANNEL_OPTION.GREEN or channel == persistence.CHANNEL_OPTION.BOTH
    if red then
        connect(holder.sender, defines.wire_connector_id.circuit_red, holder.diagnostics_cell)
    else
        disconnect(holder.sender, defines.wire_connector_id.circuit_red, holder.diagnostics_cell)
    end

    if green then
        connect(holder.sender, defines.wire_connector_id.circuit_green, holder.diagnostics_cell)
    else
        disconnect(holder.sender, defines.wire_connector_id.circuit_green, holder.diagnostics_cell)
    end
end

function _M.on_built(sender, tags)
    local surface = sender.surface
    local position = sender.position
    local reader = surface.create_entity {
        name = names.reader.CONTAINER,
        position = position,
        force = sender.force,
        create_build_effect_smoke = false,
    }
    local diagnostics = surface.create_entity {
        name = names.reader.SIGNAL_DIAGNOSTICS_CELL,
        position = position,
        force = sender.force,
        create_build_effect_smoke = false,
    }

    local cb = diagnostics.get_or_create_control_behavior()
    cb.enabled = false
    local section = cb.get_section(1)
    section.filters = { {
        value = {
            type = 'virtual',
            name = names.signal.INSERTED,
            quality = 'normal',
            comparator = '=',
        },
        min = 1,
    }, }

    local inventory = reader.get_inventory(defines.inventory.chest)
    inventory.set_filter(1, names.memorycard.ITEM)
    local holder = persistence.register_reader(sender, reader, diagnostics)
    if tags then
        if tags[tag_names.DIAGNOSTICS] ~= nil then
            holder.options.diagnostics_channel = tags[tag_names.DIAGNOSTICS]
        end
    end
    _M.apply_options(holder)
end

function _M.on_cloned(source, destination)
    local reader = find_chest(source)
    if reader == nil then return end;
    local holder = persistence.readers()[reader.unit_number]
    if holder.clones == nil then
        holder.clones = {
            total = 0,
            required = 3,
            cells = {},
        }
        if holder.cells ~= nil then
            holder.clones.required = holder.clones.required + #holder.cells
        end
    end

    if destination.name == names.reader.SIGNAL_SENDER_CELL then
        table.insert(holder.clones.cells, destination)
    else
        holder.clones[destination.name] = destination
    end
    holder.clones.total = holder.clones.total + 1
    if holder.clones.total == holder.clones.required then
        local new_holder = persistence.register_reader(
            holder.clones[names.reader.SIGNAL_SENDER],
            holder.clones[names.reader.CONTAINER],
            holder.clones[names.reader.SIGNAL_DIAGNOSTICS_CELL])
        if holder.cells ~= nil then
            new_holder.cells = holder.clones.cells
        end
        persistence.copy_reader_options(holder, new_holder)
        holder.clones = nil
    end
end

function _M.on_destroyed(entity, player_index, spill_inventory)
    local reader = entity.surface.find_entity(names.reader.CONTAINER, entity.position)
    if reader == nil then return end
    local holder = persistence.readers()[reader.unit_number]
    local unit_number = entity.unit_number
    if holder then
        persistence.delete_reader(holder)

        if player_index ~= nil then
            game.players[player_index].mine_entity(holder.reader, true)
            game.players[player_index].mine_entity(holder.sender, true)
        elseif spill_inventory then
            local inventory = holder.reader.get_inventory(defines.inventory.chest)
            utils.spill_items(entity.surface, entity.position, entity.force, inventory)
        end

        if holder.cells ~= nil then
            destroy_cells(holder)
        end
        holder.diagnostics_cell.destroy()
        if holder.reader.valid and unit_number ~= holder.reader.unit_number then
            holder.reader.destroy()
        end
        if holder.sender.valid and unit_number ~= holder.sender.unit_number then
            holder.sender.destroy()
        end
    end
end

function _M.on_tick()
    for _, holder in pairs(persistence.readers()) do
        local inventory = holder.reader.get_inventory(defines.inventory.chest)
        if not inventory.is_empty() and inventory[1].name == names.memorycard.ITEM
        then
            if holder.cells == nil then
                create_cells(holder, inventory[1])
                local cb = holder.diagnostics_cell.get_or_create_control_behavior()
                cb.enabled = true;
            end
        else
            if holder.cells ~= nil then
                destroy_cells(holder)
                local cb = holder.diagnostics_cell.get_or_create_control_behavior()
                cb.enabled = false;
            end
        end
    end
end

function _M.on_gui_opened(entity, player_index)
    local chest = find_chest(entity)
    local player = game.get_player(player_index)
    if chest and player then
        game.get_player(player_index).opened = chest
        local holder = persistence.readers()[chest.unit_number]
        gui.open_options_gui(player, holder)
    end
end

function _M.on_gui_closed(_, player_index)
    local player = game.get_player(player_index)
    if not player then return end
    gui.close_options_gui(player)
end

function _M.on_player_fast_inserted(entity, player)
    utils.fast_insert(player, find_chest(entity))
end

function _M.on_surface_erased(surface_index)
    local readers = persistence.readers()
    for key, holder in pairs(readers) do
        if holder.reader.surface_index == surface_index then
            readers[key] = nil
        end
    end
end

function _M.save_blueprint_data(entity, blueprint, index)
    local chest = find_chest(entity)
    if chest == nil then return end
    local holder = persistence.readers()[chest.unit_number]
    if holder == nil then return end
    blueprint.set_blueprint_entity_tag(index, tag_names.DIAGNOSTICS, holder.options.diagnostics_channel)
end

local function read_options(machine)
    if machine.tags ~= nil then
        return {
            diagnostics_channel = machine.tags[tag_names.DIAGNOSTICS],
        }
    end
    local reader = find_chest(machine)
    if not reader then return {} end
    local holder = persistence.readers()[reader.unit_number]
    return holder and holder.options or {}
end

local function write_options(machine, options)
    if machine.name == 'entity-ghost' then
        local tags = machine.tags or {}
        tags[tag_names.DIAGNOSTICS] = options.diagnostics_channel
        machine.tags = tags
        return true
    end
    local reader = find_chest(machine)
    if not reader then return false end
    local holder = persistence.readers()[reader.unit_number]
    if holder == nil then return false end
    persistence.copy_reader_options({ options = options, }, holder)
    _M.apply_options(holder)
end

function _M.copy_settings(source, destination, player_index)
    local options = read_options(source)
    if not options then return end
    if write_options(destination, options) then
        local player = game.players[player_index]
        player.play_sound { path = 'utility/entity_settings_pasted', }
    end
end

return _M
