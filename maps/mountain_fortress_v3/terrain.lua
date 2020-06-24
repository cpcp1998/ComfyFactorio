local Event = require 'utils.event'
local Biters = require 'modules.wave_defense.biter_rolls'
local Functions = require 'maps.mountain_fortress_v3.functions'
local WPT = require 'maps.mountain_fortress_v3.table'
local get_noise = require 'utils.get_noise'

local Public = {}

local math_random = math.random
local math_floor = math.floor
local math_abs = math.abs
Public.level_depth = 704
Public.level_width = 640
local worm_level_modifier = 0.19
local min_number_of_wagons_per_level = 1
local max_number_of_wagons_per_level = 3
local wagon_depth = 600
local wagon_width = 320

local wagon_raffle = {'cargo-wagon', 'cargo-wagon', 'cargo-wagon', 'locomotive', 'fluid-wagon'}
local rock_raffle = {
    'sand-rock-big',
    'sand-rock-big',
    'rock-big',
    'rock-big',
    'rock-big',
    'rock-big',
    'rock-big',
    'rock-big',
    'rock-big',
    'rock-big',
    'rock-huge'
}

local size_of_rock_raffle = #rock_raffle

local scrap_entities = {
    'crash-site-assembling-machine-1-broken',
    'crash-site-assembling-machine-2-broken',
    'crash-site-assembling-machine-1-broken',
    'crash-site-assembling-machine-2-broken',
    'crash-site-lab-broken',
    'medium-ship-wreck',
    'small-ship-wreck',
    'medium-ship-wreck',
    'small-ship-wreck',
    'medium-ship-wreck',
    'small-ship-wreck',
    'medium-ship-wreck',
    'small-ship-wreck',
    'crash-site-chest-1',
    'crash-site-chest-2',
    'crash-site-chest-1',
    'crash-site-chest-2',
    'crash-site-chest-1',
    'crash-site-chest-2'
}
local scrap_entities_index = #scrap_entities

local spawner_raffle = {'biter-spawner', 'biter-spawner', 'biter-spawner', 'spitter-spawner'}
local trees = {'dead-grey-trunk', 'dead-grey-trunk', 'dry-tree'}

local callback = {
    [1] = {callback = Functions.refill_turret_callback, data = Functions.firearm_magazine_ammo},
    [2] = {callback = Functions.refill_turret_callback, data = Functions.piercing_rounds_magazine_ammo},
    [3] = {callback = Functions.refill_turret_callback, data = Functions.uranium_rounds_magazine_ammo},
    [4] = {callback = Functions.power_source_callback, data = Functions.laser_turrent_power_source},
    [5] = {callback = Functions.refill_liquid_turret_callback, data = Functions.light_oil_ammo},
    [6] = {callback = Functions.refill_turret_callback, data = Functions.artillery_shell_ammo}
}

local turret_list = {
    [1] = {name = 'gun-turret', callback = callback[1]},
    [2] = {name = 'gun-turret', callback = callback[2]},
    [3] = {name = 'gun-turret', callback = callback[3]},
    [4] = {name = 'laser-turret', callback = callback[4]},
    [5] = {name = 'flamethrower-turret', callback = callback[5]},
    [6] = {name = 'artillery-turret', callback = callback[6]}
}

local function place_wagon(x, y, data)
    local index = math_floor(math_abs(y / Public.level_depth))
    local wagon_location = WPT.get().wagon_location
    if not wagon_location[index] then
        local loc = {}
        for _ = 1, math_random(min_number_of_wagons_per_level, max_number_of_wagons_per_level), 1 do
            loc[#loc+1] = {
                x = (math_random()-0.5) * wagon_width,
                y = - math_random()*wagon_depth - index*Public.level_depth - (Public.level_depth-wagon_depth)/2,
            }
        end
        wagon_location[index] = loc
    end

    local legal = false
    for key, pos in pairs(wagon_location[index]) do
        if math_abs(pos.x - x) < 0.6 and math_abs(pos.y - y) < 0.6 then
            legal = true
            wagon_location[index][key] = nil
            break
        end
    end
    if not legal then
        return
    end

    local surface = data.surface
    local tiles = data.tiles
    local entities = data.entities
    local position = {x = x, y = y}
    local wagon_mineable = {
        callback = Functions.disable_minable_and_ICW_callback
    }

    local location
    local direction
    local r1 = math_random(2, 4) * 2
    local r2 = math_random(2, 4) * 2

    if math_random(1, 2) == 1 then
        location =
            surface.find_tiles_filtered({area = {{position.x, position.y - r1}, {position.x + 2, position.y + r2}}})
        direction = 0
    else
        location =
            surface.find_tiles_filtered({area = {{position.x - r1, position.y}, {position.x + r2, position.y + 2}}})
        direction = 2
    end

    for k, tile in pairs(location) do
        if tile.collides_with('resource-layer') then
            tiles[#tiles + 1] = {name = 'landfill', position = tile.position}
        end
        for _, e in pairs(surface.find_entities_filtered({position = tile.position, force = {'neutral', 'enemy'}})) do
            e.destroy()
        end
        if tile.position.y % 2 == 0 and tile.position.x % 2 == 0 then
            entities[#entities + 1] = {
                name = 'straight-rail',
                position = tile.position,
                force = 'player',
                direction = direction
            }
        end
    end

    table.insert(
        entities,
        {
            name = wagon_raffle[math_random(1, #wagon_raffle)],
            position = position,
            force = 'player',
            callback = wagon_mineable
        }
    )
    return true
end

local function get_oil_amount(p)
    return (math_abs(p.y) * 200 + 10000) * math_random(75, 125) * 0.01
end

function Public.increment_value(tbl)
    tbl.yv = tbl.yv + 1

    if tbl.yv == 32 then
        if tbl.xv == 32 then
            tbl.xv = 0
        end
        if tbl.yv == 32 then
            tbl.yv = 0
        end
        tbl.xv = tbl.xv + 1
    end

    return tbl.xv, tbl.yv
end

local function spawn_turret(entities, p, probability)
    entities[#entities + 1] = {
        name = turret_list[probability].name,
        position = p,
        force = 'enemy',
        callback = turret_list[probability].callback,
        direction = 4,
        collision = true
    }
end

local function wall(data)
    local tiles = data.tiles
    local entities = data.entities
    local surface = data.surface
    local treasure = data.treasure
    local stone_wall = {callback = Functions.disable_minable_callback}

    local x, y = Public.increment_value(data)

    local seed = data.seed
    local p = {x = x + data.top_x, y = y + data.top_y}

    local small_caves = get_noise('small_caves', p, seed + 12300)
    local cave_ponds = get_noise('cave_rivers', p, seed + 150000)
    if y > 9 + cave_ponds * 6 and y < 23 + small_caves * 6 then
        if small_caves > 0.02 or cave_ponds > 0.02 then
            if small_caves > 0.005 then
                tiles[#tiles + 1] = {name = 'water', position = p}
            else
                tiles[#tiles + 1] = {name = 'water-shallow', position = p}
                if math_random(1, 32) == 1 then
                    entities[#entities + 1] = {
                        name = 'land-mine',
                        position = p,
                        force = 'enemy'
                    }
                end
            end
            if math_random(1, 48) == 1 then
                entities[#entities + 1] = {name = 'fish', position = p}
            end
        else
            tiles[#tiles + 1] = {name = 'tutorial-grid', position = p}

            if math_random(1, 5) ~= 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, #rock_raffle)], position = p}
                if math_random(1, 32) == 1 then
                    entities[#entities + 1] = {
                        name = 'land-mine',
                        position = p,
                        force = 'enemy'
                    }
                end
            end
        end
    else
        tiles[#tiles + 1] = {name = 'tutorial-grid', position = p}

        if
            surface.can_place_entity(
                {
                    name = 'stone-wall',
                    position = p,
                    force = 'enemy'
                }
            )
         then
            if math_random(1, 512) == 1 and y > 3 and y < 28 then
                if math_random(1, 2) == 1 then
                    treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
                else
                    treasure[#treasure + 1] = {position = p, chest = 'steel-chest'}
                end
            else
                if y < 4 or y > 25 then
                    if y <= 24 then
                        if math_random(1, y + 1) == 1 then
                            entities[#entities + 1] = {
                                name = 'stone-wall',
                                position = p,
                                force = 'player',
                                callback = stone_wall
                            }
                        end
                    else
                        if math_random(1, 32 - y) == 1 then
                            entities[#entities + 1] = {
                                name = 'stone-wall',
                                position = p,
                                force = 'player',
                                callback = stone_wall
                            }
                        end
                    end
                end
            end
        end

        if math_random(1, 48) == 1 then
            if
                surface.can_place_entity(
                    {
                        name = 'medium-worm-turret',
                        position = p,
                        force = 'enemy'
                    }
                )
             then
                Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
                entities[#entities + 1] = {
                    name = Biters.wave_defense_roll_worm_name(),
                    position = p,
                    force = 'enemy'
                }
            end
        end

        if math_random(1, 48) == 1 then
            if math_abs(p.y) < Public.level_depth * 1.5 then
                if math_random(1, 16) == 1 then
                    spawn_turret(entities, p, 1)
                else
                    spawn_turret(entities, p, 2)
                end
            elseif math_abs(p.y) < Public.level_depth * 2.5 then
                if math_random(1, 8) == 1 then
                    spawn_turret(entities, p, 3)
                end
            elseif math_abs(p.y) < Public.level_depth * 3.5 then
                if math_random(1, 4) == 1 then
                    spawn_turret(entities, p, 4)
                else
                    spawn_turret(entities, p, 3)
                end
            elseif math_abs(p.y) < Public.level_depth * 4.5 then
                if math_random(1, 4) == 1 then
                    spawn_turret(entities, p, 4)
                else
                    spawn_turret(entities, p, 5)
                end
            elseif math_abs(p.y) < Public.level_depth * 5.5 then
                if math_random(1, 4) == 1 then
                    spawn_turret(entities, p, 4)
                elseif math_random(1, 2) == 1 then
                    spawn_turret(entities, p, 5)
                elseif math_random(1, 8) == 1 then
                    spawn_turret(entities, p, 6)
                end
            end
        elseif math_abs(p.y) > Public.level_depth * 5.5 then
            if math_random(1, 32) == 1 then
                spawn_turret(entities, p, math_random(3, 6))
            end
        end
    end
end

local function process_level_13_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local treasure = data.treasure

    local small_caves = get_noise('small_caves', p, seed)
    local noise_cave_ponds = get_noise('cave_ponds', p, seed)

    if small_caves > -0.22 and small_caves < 0.22 then
        tiles[#tiles + 1] = {name = 'dirt-3', position = p}
        if math_random(1, 768) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        if math_random(1, 2) == 1 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        return
    end

    if small_caves < -0.35 or small_caves > 0.35 then
        tiles[#tiles + 1] = {name = 'deepwater-green', position = p}
        if math_random(1, 128) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        if math_random(1, 128) == 1 then
            Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
            entities[#entities + 1] = {name = Biters.wave_defense_roll_worm_name(), position = p, force = 'enemy'}
        end
        if math_random(1, 256) == 1 then
            spawn_turret(entities, p, 4)
        end
        return
    end

    if small_caves > -0.40 and small_caves < 0.40 then
        if noise_cave_ponds > 0.35 then
            tiles[#tiles + 1] = {name = 'dirt-' .. math_random(1, 4), position = p}
            if math_random(1, 256) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
            if math_random(1, 256) == 1 then
                entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
            end
            return
        end
        if noise_cave_ponds > 0.25 then
            tiles[#tiles + 1] = {name = 'dirt-7', position = p}
            if math_random(1, 512) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
            if math_random(1, 2) == 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
            end
            return
        end
    end

    tiles[#tiles + 1] = {name = 'water-shallow', position = p}
end

local function process_level_12_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local noise_1 = get_noise('small_caves', p, seed)
    local noise_2 = get_noise('no_rocks_2', p, seed + 20000)

    if noise_1 > 0.65 then
        if math_random(1, 100) > 88 then
            entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
        else
            if math_random(1, 2) == 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
            end
        end
        if math_random(1, 48) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end

    if noise_1 < -0.72 then
        tiles[#tiles + 1] = {name = 'lab-dark-2', position = p}
        if math_random(1, 100) > 88 then
            entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
        end
        return
    end

    if noise_1 > -0.30 and noise_1 < 0.30 then
        if noise_1 > -0.14 and noise_1 < 0.14 then
            tiles[#tiles + 1] = {name = 'dirt-7', position = p}
            if math_random(1, 2) == 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
            end
            if math_random(1, 256) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
        else
            tiles[#tiles + 1] = {name = 'water-shallow', position = p}
        end
        return
    end

    if math_random(1, 64) == 1 and noise_2 > 0.65 then
        if math_random(1, 32) == 1 then
            entities[#entities + 1] = {name = 'stone', position = p, amount = math_abs(p.y) + 1}
        elseif math_random(1, 32) == 1 then
            entities[#entities + 1] = {name = 'iron-ore', position = p, amount = math_abs(p.y) + 1}
        elseif math_random(1, 32) == 1 then
            entities[#entities + 1] = {name = 'copper-ore', position = p, amount = math_abs(p.y) + 1}
        elseif math_random(1, 32) == 1 then
            entities[#entities + 1] = {name = 'coal', position = p, amount = math_abs(p.y) + 1}
        end
    end
    if math_random(1, 8192) == 1 then
        markets[#markets + 1] = p
    end
    if math_random(1, 1024) == 1 then
        entities[#entities + 1] = {
            name = 'crash-site-chest-' .. math_random(1, 2),
            position = p,
            force = 'neutral'
        }
    end

    tiles[#tiles + 1] = {name = 'lab-dark-2', position = p}
end

local function process_level_11_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local noise_1 = get_noise('small_caves', p, seed)
    local noise_2 = get_noise('no_rocks_2', p, seed + 10000)

    if noise_1 > 0.7 then
        tiles[#tiles + 1] = {name = 'water', position = p}
        if math_random(1, 48) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end

    if noise_1 < -0.72 then
        tiles[#tiles + 1] = {name = 'lab-dark-1', position = p}
        entities[#entities + 1] = {name = 'uranium-ore', position = p, amount = math_abs(p.y) + 1 * 3}
        return
    end

    if noise_1 > -0.30 and noise_1 < 0.30 then
        if noise_1 > -0.14 and noise_1 < 0.14 then
            tiles[#tiles + 1] = {name = 'dirt-7', position = p}
            if math_random(1, 2) == 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
            end
            if math_random(1, 256) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
        else
            tiles[#tiles + 1] = {name = 'water-shallow', position = p}
        end
        return
    end

    if math_random(1, 64) == 1 and noise_2 > 0.65 then
        entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
    end
    if math_random(1, 8192) == 1 then
        markets[#markets + 1] = p
    end
    if math_random(1, 1024) == 1 then
        entities[#entities + 1] = {
            name = 'crash-site-chest-' .. math_random(1, 2),
            position = p,
            force = 'neutral'
        }
    end

    tiles[#tiles + 1] = {name = 'tutorial-grid', position = p}
end

local function process_level_10_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local treasure = data.treasure

    local scrapyard = get_noise('scrapyard', p, seed)

    if scrapyard < -0.70 or scrapyard > 0.70 then
        tiles[#tiles + 1] = {name = 'grass-3', position = p}
        if math_random(1, 40) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        return
    end

    if scrapyard < -0.65 or scrapyard > 0.65 then
        tiles[#tiles + 1] = {name = 'water-green', position = p}
        return
    end
    if math_abs(scrapyard) > 0.40 and math_abs(scrapyard) < 0.65 then
        if math_random(1, 64) == 1 then
            Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
            entities[#entities + 1] = {name = Biters.wave_defense_roll_worm_name(), position = p, force = 'enemy'}
        end
        tiles[#tiles + 1] = {name = 'water-mud', position = p}
        return
    end
    if math_abs(scrapyard) > 0.25 and math_abs(scrapyard) < 0.40 then
        if math_random(1, 128) == 1 then
            Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
            entities[#entities + 1] = {name = Biters.wave_defense_roll_worm_name(), position = p, force = 'enemy'}
        end
        if math_random(1, 256) == 1 then
            spawn_turret(entities, p, 4)
        end
        tiles[#tiles + 1] = {name = 'water-shallow', position = p}
        return
    end
    if scrapyard > -0.15 and scrapyard < 0.15 then
        if math_random(1, 100) > 88 then
            entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
        else
            if math_random(1, 2) == 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
            end
        end
        tiles[#tiles + 1] = {name = 'dirt-6', position = p}
        return
    end
    tiles[#tiles + 1] = {name = 'grass-2', position = p}
end

local function process_level_9_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local maze_p = {x = math_floor(p.x - p.x % 10), y = math_floor(p.y - p.y % 10)}
    local maze_noise = get_noise('no_rocks_2', maze_p, seed)

    if maze_noise > -0.35 and maze_noise < 0.35 then
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        local no_rocks_2 = get_noise('no_rocks_2', p, seed)
        if math_random(1, 2) == 1 and no_rocks_2 > -0.5 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        if math_random(1, 1024) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        if math_random(1, 256) == 1 then
            Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
            entities[#entities + 1] = {name = Biters.wave_defense_roll_worm_name(), position = p, force = 'enemy'}
        end
        return
    end

    if maze_noise > 0 and maze_noise < 0.45 then
        if math_random(1, 512) == 1 then
            markets[#markets + 1] = p
        end
        if math_random(1, 256) == 1 then
            entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
        end
        if math_random(1, 32) == 1 then
            entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
        end
        return
    end

    if maze_noise < -0.5 or maze_noise > 0.5 then
        tiles[#tiles + 1] = {name = 'deepwater', position = p}
        if math_random(1, 96) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end

    tiles[#tiles + 1] = {name = 'water', position = p}
    if math_random(1, 96) == 1 then
        entities[#entities + 1] = {name = 'fish', position = p}
    end
end

--SCRAPYARD
local function process_level_8_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities

    local scrapyard = get_noise('scrapyard', p, seed)

    --Chasms
    local noise_cave_ponds = get_noise('cave_ponds', p, seed)
    local small_caves = get_noise('small_caves', p, seed)
    if noise_cave_ponds < 0.15 and noise_cave_ponds > -0.15 then
        if small_caves > 0.35 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end

        if small_caves < -0.35 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end
    end

    if scrapyard < -0.25 or scrapyard > 0.25 then
        if math_random(1, 256) == 1 then
            if math_random(1, 8) == 1 then
                spawn_turret(entities, p, 3)
            else
                spawn_turret(entities, p, 4)
            end
        end
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        if scrapyard < -0.55 or scrapyard > 0.55 then
            if math_random(1, 2) == 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
            end
            return
        end
        if scrapyard < -0.28 or scrapyard > 0.28 then
            if math_random(1, 128) == 1 then
                Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
                entities[#entities + 1] = {name = Biters.wave_defense_roll_worm_name(), position = p, force = 'enemy'}
            end
            if math_random(1, 96) == 1 then
                entities[#entities + 1] = {
                    name = scrap_entities[math_random(1, scrap_entities_index)],
                    position = p,
                    force = 'enemy'
                }
            end
            if math_random(1, 5) > 1 then
                entities[#entities + 1] = {name = 'mineable-wreckage', position = p}
            end
            if math_random(1, 256) == 1 then
                entities[#entities + 1] = {name = 'land-mine', position = p, force = 'enemy'}
            end
            return
        end
        return
    end

    local cave_ponds = get_noise('cave_ponds', p, seed)
    if cave_ponds < -0.6 and scrapyard > -0.2 and scrapyard < 0.2 then
        tiles[#tiles + 1] = {name = 'deepwater-green', position = p}
        if math_random(1, 128) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end

    local large_caves = get_noise('large_caves', p, seed)
    if scrapyard > -0.15 and scrapyard < 0.15 then
        if math_floor(large_caves * 10) % 4 < 3 then
            tiles[#tiles + 1] = {name = 'dirt-7', position = p}
            if math_random(1, 2) == 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
            end
            return
        end
    end

    if math_random(1, 64) == 1 and cave_ponds > 0.6 then
        entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
    end

    tiles[#tiles + 1] = {name = 'stone-path', position = p}
    if math_random(1, 256) == 1 then
        entities[#entities + 1] = {name = 'land-mine', position = p, force = 'enemy'}
    end
end

local function process_level_7_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local cave_rivers_3 = get_noise('cave_rivers_3', p, seed)
    local cave_rivers_4 = get_noise('cave_rivers_4', p, seed + 50000)
    local no_rocks_2 = get_noise('no_rocks_2', p, seed)

    if cave_rivers_3 > -0.025 and cave_rivers_3 < 0.025 and no_rocks_2 > -0.6 then
        tiles[#tiles + 1] = {name = 'water', position = p}
        if math_random(1, 128) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end

    if cave_rivers_4 > -0.025 and cave_rivers_4 < 0.025 and no_rocks_2 > -0.6 then
        tiles[#tiles + 1] = {name = 'water', position = p}
        if math_random(1, 128) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end

    local noise_ores = get_noise('no_rocks_2', p, seed + 25000)

    if cave_rivers_3 > -0.20 and cave_rivers_3 < 0.20 then
        tiles[#tiles + 1] = {name = 'grass-' .. math_floor(cave_rivers_3 * 32) % 3 + 1, position = p}
        if cave_rivers_3 > -0.10 and cave_rivers_3 < 0.10 then
            if math_random(1, 8) == 1 and no_rocks_2 > -0.25 then
                entities[#entities + 1] = {name = 'tree-01', position = p}
            end
            if math_random(1, 2048) == 1 then
                markets[#markets + 1] = p
            end
            if noise_ores < -0.5 and no_rocks_2 > -0.6 then
                if cave_rivers_3 > 0 and cave_rivers_3 < 0.07 then
                    entities[#entities + 1] = {name = 'iron-ore', position = p, amount = math_abs(p.y) + 1}
                end
            end
        end
        if math_random(1, 64) == 1 and no_rocks_2 > 0.7 then
            entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
        end
        if math_random(1, 2048) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        return
    end

    if cave_rivers_4 > -0.20 and cave_rivers_4 < 0.20 then
        tiles[#tiles + 1] = {name = 'grass-' .. math_floor(cave_rivers_4 * 32) % 3 + 1, position = p}
        if cave_rivers_4 > -0.10 and cave_rivers_4 < 0.10 then
            if math_random(1, 8) == 1 and no_rocks_2 > -0.25 then
                entities[#entities + 1] = {name = 'tree-02', position = p}
            end
            if math_random(1, 2048) == 1 then
                markets[#markets + 1] = p
            end
            if noise_ores < -0.5 and no_rocks_2 > -0.6 then
                if cave_rivers_4 > 0 and cave_rivers_4 < 0.07 then
                    entities[#entities + 1] = {name = 'copper-ore', position = p, amount = math_abs(p.y) + 1}
                end
            end
        end
        if math_random(1, 64) == 1 and no_rocks_2 > 0.7 then
            entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
        end
        if math_random(1, 2048) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        return
    end

    --Chasms
    local noise_cave_ponds = get_noise('cave_ponds', p, seed)
    local small_caves = get_noise('small_caves', p, seed)
    if noise_cave_ponds < 0.25 and noise_cave_ponds > -0.25 then
        if small_caves > 0.55 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end

        if small_caves < -0.55 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}

            return
        end
    end

    tiles[#tiles + 1] = {name = 'dirt-7', position = p}
    if math_random(1, 100) > 15 then
        entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
    end
    if math_random(1, 256) == 1 then
        treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
    end
end

local function process_level_6_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local large_caves = get_noise('large_caves', p, seed)
    local cave_rivers = get_noise('cave_rivers', p, seed)

    --Chasms
    local noise_cave_ponds = get_noise('cave_ponds', p, seed)
    local small_caves = get_noise('small_caves', p, seed)
    if noise_cave_ponds < 0.45 and noise_cave_ponds > -0.45 then
        if small_caves > 0.45 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end

        if small_caves < -0.45 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end
    end

    if large_caves > -0.03 and large_caves < 0.03 and cave_rivers < 0.25 then
        tiles[#tiles + 1] = {name = 'water-green', position = p}
        if math_random(1, 128) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end

    if cave_rivers > -0.1 and cave_rivers < 0.1 then
        if math_random(1, 36) == 1 then
            entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
        end
        if math_random(1, 128) == 1 then
            Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
            entities[#entities + 1] = {name = Biters.wave_defense_roll_worm_name(), position = p, force = 'enemy'}
        end
        if math_random(1, 256) == 1 then
            spawn_turret(entities, p, 4)
        end
    else
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        if math_random(1, 100) > 15 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        if math_random(1, 512) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        if math_random(1, 4096) == 1 then
            entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
        end
        if math_random(1, 8096) == 1 then
            markets[#markets + 1] = p
        end
    end
end

local function process_level_5_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local treasure = data.treasure

    local small_caves = get_noise('small_caves', p, seed)
    local noise_cave_ponds = get_noise('cave_ponds', p, seed)

    if small_caves > -0.24 and small_caves < 0.24 then
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        if math_random(1, 768) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        if math_random(1, 2) == 1 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        return
    end

    if small_caves < -0.50 or small_caves > 0.50 then
        tiles[#tiles + 1] = {name = 'deepwater-green', position = p}
        if math_random(1, 128) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        if math_random(1, 128) == 1 then
            Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
            entities[#entities + 1] = {name = Biters.wave_defense_roll_worm_name(), position = p, force = 'enemy'}
        end
        if math_random(1, 256) == 1 then
            spawn_turret(entities, p, 4)
        end
        return
    end

    if small_caves > -0.40 and small_caves < 0.40 then
        if noise_cave_ponds > 0.35 then
            tiles[#tiles + 1] = {name = 'dirt-' .. math_random(1, 4), position = p}
            if math_random(1, 256) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
            if math_random(1, 256) == 1 then
                entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
            end
            return
        end
        if noise_cave_ponds > 0.25 then
            tiles[#tiles + 1] = {name = 'dirt-7', position = p}
            if math_random(1, 512) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
            if math_random(1, 2) == 1 then
                entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
            end
        end
    end

    tiles[#tiles + 1] = {name = 'out-of-map', position = p}
end

local function process_level_4_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local noise_large_caves = get_noise('large_caves', p, seed)
    local noise_cave_ponds = get_noise('cave_ponds', p, seed)
    local small_caves = get_noise('small_caves', p, seed)

    if math_abs(noise_large_caves) > 0.7 then
        tiles[#tiles + 1] = {name = 'water', position = p}
        if math_random(1, 16) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end
    if math_abs(noise_large_caves) > 0.6 then
        if math_random(1, 16) == 1 then
            entities[#entities + 1] = {name = 'tree-02', position = p}
        end
        if math_random(1, 32) == 1 then
            markets[#markets + 1] = p
        end
    end
    if math_abs(noise_large_caves) > 0.5 then
        tiles[#tiles + 1] = {name = 'grass-2', position = p}
        if math_random(1, 620) == 1 then
            entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
        end
        if math_random(1, 384) == 1 then
            Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
            entities[#entities + 1] = {name = Biters.wave_defense_roll_worm_name(), position = p, force = 'enemy'}
        end
        if math_random(1, 1024) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        return
    end
    if math_abs(noise_large_caves) > 0.475 then
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        if math_random(1, 2) == 1 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        if math_random(1, 2048) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        return
    end

    --Chasms
    if noise_cave_ponds < 0.15 and noise_cave_ponds > -0.15 then
        if small_caves > 0.75 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end

        if small_caves < -0.75 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end
    end

    if small_caves > -0.15 and small_caves < 0.15 then
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        if math_random(1, 2) == 1 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        if math_random(1, 1024) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        return
    end

    if noise_large_caves > -0.2 and noise_large_caves < 0.2 then
        --Main Rock Terrain
        local no_rocks_2 = get_noise('no_rocks_2', p, seed + 75000)
        if no_rocks_2 > 0.80 or no_rocks_2 < -0.80 then
            tiles[#tiles + 1] = {name = 'dirt-' .. math_floor(no_rocks_2 * 8) % 2 + 5, position = p}
            if math_random(1, 512) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
            return
        end

        if math_random(1, 2048) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        if math_random(1, 100) > 30 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        return
    end

    tiles[#tiles + 1] = {name = 'out-of-map', position = p}
end

local function process_level_3_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local small_caves = get_noise('small_caves', p, seed + 50000)
    local small_caves_2 = get_noise('small_caves_2', p, seed + 70000)
    local noise_large_caves = get_noise('large_caves', p, seed + 60000)
    local noise_cave_ponds = get_noise('cave_ponds', p, seed)

    --Market Spots
    if noise_cave_ponds < -0.77 then
        if noise_cave_ponds > -0.79 then
            tiles[#tiles + 1] = {name = 'dirt-7', position = p}
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        else
            tiles[#tiles + 1] = {name = 'grass-' .. math_floor(noise_cave_ponds * 32) % 3 + 1, position = p}
            if math_random(1, 32) == 1 then
                markets[#markets + 1] = p
            end
            if math_random(1, 16) == 1 then
                entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
            end
        end
        return
    end

    if noise_large_caves > -0.15 and noise_large_caves < 0.15 or small_caves_2 > 0 then
        --Green Water Ponds
        if noise_cave_ponds > 0.80 then
            tiles[#tiles + 1] = {name = 'deepwater-green', position = p}
            if math_random(1, 16) == 1 then
                entities[#entities + 1] = {name = 'fish', position = p}
            end
            return
        end

        --Chasms
        if noise_cave_ponds < 0.12 and noise_cave_ponds > -0.12 then
            if small_caves > 0.85 then
                tiles[#tiles + 1] = {name = 'out-of-map', position = p}

                return
            end

            if small_caves < -0.85 then
                tiles[#tiles + 1] = {name = 'out-of-map', position = p}

                return
            end
        end

        --Rivers
        local cave_rivers = get_noise('cave_rivers', p, seed + 100000)
        if cave_rivers < 0.024 and cave_rivers > -0.024 then
            if noise_cave_ponds > 0.2 then
                tiles[#tiles + 1] = {name = 'water-shallow', position = p}
                if math_random(1, 64) == 1 then
                    entities[#entities + 1] = {name = 'fish', position = p}
                end
                return
            end
        end
        local cave_rivers_2 = get_noise('cave_rivers_2', p, seed)
        if cave_rivers_2 < 0.024 and cave_rivers_2 > -0.024 then
            if noise_cave_ponds < 0.4 then
                tiles[#tiles + 1] = {name = 'water-shallow', position = p}
                if math_random(1, 64) == 1 then
                    entities[#entities + 1] = {name = 'fish', position = p}
                end
                return
            end
        end

        if noise_cave_ponds > 0.725 then
            tiles[#tiles + 1] = {name = 'dirt-' .. math_random(4, 6), position = p}
            return
        end

        local no_rocks = get_noise('no_rocks', p, seed + 25000)
        --Worm oil Zones
        if no_rocks < 0.20 and no_rocks > -0.20 then
            if small_caves > 0.35 then
                tiles[#tiles + 1] = {name = 'dirt-' .. math_floor(noise_cave_ponds * 32) % 7 + 1, position = p}
                if math_random(1, 320) == 1 then
                    entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
                end
                if math_random(1, 50) == 1 then
                    Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
                    entities[#entities + 1] = {
                        name = Biters.wave_defense_roll_worm_name(),
                        position = p,
                        force = 'enemy'
                    }
                end
                if math_random(1, 256) == 1 then
                    spawn_turret(entities, p, 3)
                end
                if math_random(1, 512) == 1 then
                    treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
                end
                if math_random(1, 64) == 1 then
                    entities[#entities + 1] = {name = 'dead-tree-desert', position = p}
                end
                return
            end
        end

        --Main Rock Terrain
        local no_rocks_2 = get_noise('no_rocks_2', p, seed + 75000)
        if no_rocks_2 > 0.80 or no_rocks_2 < -0.80 then
            tiles[#tiles + 1] = {name = 'dirt-' .. math_floor(no_rocks_2 * 8) % 2 + 5, position = p}
            if math_random(1, 512) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
            return
        end

        if math_random(1, 2048) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        if math_random(1, 100) > 30 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        return
    end

    tiles[#tiles + 1] = {name = 'out-of-map', position = p}
end

local function process_level_2_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local small_caves = get_noise('small_caves', p, seed)
    local noise_large_caves = get_noise('large_caves', p, seed)

    if noise_large_caves > -0.75 and noise_large_caves < 0.75 then
        local noise_cave_ponds = get_noise('cave_ponds', p, seed)

        --Chasms
        if noise_cave_ponds < 0.15 and noise_cave_ponds > -0.15 then
            if small_caves > 0.32 then
                tiles[#tiles + 1] = {name = 'out-of-map', position = p}

                return
            end
            if small_caves < -0.32 then
                tiles[#tiles + 1] = {name = 'out-of-map', position = p}
                return
            end
        end

        --Green Water Ponds
        if noise_cave_ponds > 0.80 then
            tiles[#tiles + 1] = {name = 'deepwater-green', position = p}
            if math_random(1, 16) == 1 then
                entities[#entities + 1] = {name = 'fish', position = p}
            end
            return
        end

        --Rivers
        local cave_rivers = get_noise('cave_rivers', p, seed + 100000)
        if cave_rivers < 0.037 and cave_rivers > -0.037 then
            if noise_cave_ponds < 0.1 then
                tiles[#tiles + 1] = {name = 'water-shallow', position = p}
                if math_random(1, 64) == 1 then
                    entities[#entities + 1] = {name = 'fish', position = p}
                end
                return
            end
        end

        if noise_cave_ponds > 0.66 then
            tiles[#tiles + 1] = {name = 'dirt-' .. math_random(4, 6), position = p}
            return
        end

        --Market Spots
        if noise_cave_ponds < -0.80 then
            tiles[#tiles + 1] = {name = 'grass-' .. math_floor(noise_cave_ponds * 32) % 3 + 1, position = p}
            if math_random(1, 32) == 1 then
                markets[#markets + 1] = p
            end
            if math_random(1, 16) == 1 then
                entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
            end
            return
        end

        local no_rocks = get_noise('no_rocks', p, seed + 25000)
        --Worm oil Zones
        if no_rocks < 0.20 and no_rocks > -0.20 then
            if small_caves > 0.30 then
                tiles[#tiles + 1] = {name = 'dirt-' .. math_floor(noise_cave_ponds * 32) % 7 + 1, position = p}
                if math_random(1, 450) == 1 then
                    entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
                end
                if math_random(1, 64) == 1 then
                    Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
                    entities[#entities + 1] = {
                        name = Biters.wave_defense_roll_worm_name(),
                        position = p,
                        force = 'enemy'
                    }
                end
                if math_random(1, 256) == 1 then
                    spawn_turret(entities, p, 2)
                end
                if math_random(1, 1024) == 1 then
                    treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
                end
                if math_random(1, 64) == 1 then
                    entities[#entities + 1] = {name = 'dead-tree-desert', position = p}
                end
                return
            end
        end

        --Main Rock Terrain
        local no_rocks_2 = get_noise('no_rocks_2', p, seed + 75000)
        if no_rocks_2 > 0.80 or no_rocks_2 < -0.80 then
            tiles[#tiles + 1] = {name = 'dirt-' .. math_floor(no_rocks_2 * 8) % 2 + 5, position = p}
            if math_random(1, 512) == 1 then
                treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
            end
            return
        end

        if math_random(1, 2048) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'wooden-chest'}
        end
        tiles[#tiles + 1] = {name = 'dirt-7', position = p}
        if math_random(1, 100) > 25 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
        end
        return
    end

    tiles[#tiles + 1] = {name = 'out-of-map', position = p}
end

local function process_level_1_position(x, y, data)
    local p = {x = x, y = y}
    local seed = data.seed
    local tiles = data.tiles
    local entities = data.entities
    local markets = data.markets
    local treasure = data.treasure

    local small_caves = get_noise('small_caves', p, seed)

    local noise_cave_ponds = get_noise('cave_ponds', p, seed)

    --Chasms
    if noise_cave_ponds < 0.111 and noise_cave_ponds > -0.112 then
        if small_caves > 0.53 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end
        if small_caves < -0.53 then
            tiles[#tiles + 1] = {name = 'out-of-map', position = p}
            return
        end
    end

    --Water Ponds
    if noise_cave_ponds > 0.810 then
        tiles[#tiles + 1] = {name = 'deepwater', position = p}
        if math_random(1, 16) == 1 then
            entities[#entities + 1] = {name = 'fish', position = p}
        end
        return
    end

    --Rivers
    local cave_rivers = get_noise('cave_rivers', p, seed + 100000)
    if cave_rivers < 0.042 and cave_rivers > -0.042 then
        if noise_cave_ponds > 0 then
            tiles[#tiles + 1] = {name = 'water-shallow', position = p}
            if math_random(1, 64) == 1 then
                entities[#entities + 1] = {name = 'fish', position = p}
            end
            return
        end
    end

    if noise_cave_ponds > 0.74 then
        tiles[#tiles + 1] = {name = 'dirt-' .. math_random(4, 6), position = p}
        tiles[#tiles + 1] = {name = 'grass-1', position = p}
        if cave_rivers < -0.502 then
            tiles[#tiles + 1] = {name = 'refined-hazard-concrete-right', position = p}
        end
        if math_random(1, 64) == 1 then
            entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
        end
        return
    end

    --Market Spots
    if noise_cave_ponds < -0.74 then
        tiles[#tiles + 1] = {name = 'grass-' .. math_floor(noise_cave_ponds * 32) % 3 + 1, position = p}
        if math_random(1, 32) == 1 then
            markets[#markets + 1] = p
        end
        if math_random(1, 32) == 1 then
            entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
        end
        return
    end

    local no_rocks = get_noise('no_rocks', p, seed + 25000)
    --Worm oil Zones
    if p.y < -64 + noise_cave_ponds * 10 then
        if no_rocks < 0.12 and no_rocks > -0.12 then
            if small_caves > 0.30 then
                tiles[#tiles + 1] = {name = 'dirt-' .. math_floor(noise_cave_ponds * 32) % 7 + 1, position = p}
                if math_random(1, 450) == 1 then
                    entities[#entities + 1] = {name = 'crude-oil', position = p, amount = get_oil_amount(p)}
                end
                if math_random(1, 96) == 1 then
                    Biters.wave_defense_set_worm_raffle(math_abs(p.y) * worm_level_modifier)
                    entities[#entities + 1] = {
                        name = Biters.wave_defense_roll_worm_name(),
                        position = p,
                        force = 'enemy'
                    }
                end

                if math_random(1, 1024) == 1 then
                    treasure[#treasure + 1] = {position = p, chest = 'iron-chest'}
                end
                if math_random(1, 64) == 1 then
                    entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
                end
                return
            end
        end
    end

    --Main Rock Terrain
    local no_rocks_2 = get_noise('no_rocks_2', p, seed + 75000)
    if no_rocks_2 > 0.66 or no_rocks_2 < -0.66 then
        tiles[#tiles + 1] = {name = 'dirt-' .. math_floor(no_rocks_2 * 8) % 2 + 5, position = p}
        if math_random(1, 32) == 1 then
            entities[#entities + 1] = {name = 'tree-0' .. math_random(1, 9), position = p}
        end
        if math_random(1, 512) == 1 then
            treasure[#treasure + 1] = {position = p, chest = 'iron-chest'}
        end
        return
    end

    if math_random(1, 2048) == 1 then
        treasure[#treasure + 1] = {position = p, chest = 'iron-chest'}
    end
    tiles[#tiles + 1] = {name = 'dirt-7', position = p}
    if math_random(1, 100) > 25 then
        entities[#entities + 1] = {name = rock_raffle[math_random(1, size_of_rock_raffle)], position = p}
    end
end

Public.levels = {
    process_level_1_position,
    process_level_2_position,
    process_level_3_position,
    process_level_4_position,
    process_level_5_position,
    process_level_6_position,
    process_level_7_position,
    process_level_8_position,
    process_level_9_position,
    process_level_10_position,
    process_level_11_position,
    process_level_12_position,
    process_level_13_position
}

local function is_out_of_map(p)
    if p.x < 480 and p.x >= -480 then
        return
    end
    return true
end

local function process_bits(x, y, data)
    local left_top_y = data.area.left_top.y
    local index = math_floor((math_abs(left_top_y / Public.level_depth)) % 13) + 1
    local process_level = Public.levels[index]
    if not process_level then
        process_level = Public.levels[#Public.levels]
    end

    process_level(x, y, data)
end

local function border_chunk(data)
    local surface = data.surface
    local entities = data.entities
    local decoratives = data.decoratives
    local top_x = data.top_x
    local top_y = data.top_y

    local x, y = Public.increment_value(data)

    local pos = {x = x + data.top_x, y = y + data.top_y}

    if math_random(1, math.ceil(pos.y + pos.y) + 64) == 1 then
        entities[#entities + 1] = {name = trees[math_random(1, #trees)], position = pos}
    end
    if not is_out_of_map(pos) then
        if math_random(1, math.ceil(pos.y + pos.y) + 32) == 1 then
            entities[#entities + 1] = {name = rock_raffle[math_random(1, #rock_raffle)], position = pos}
        end
        if math_random(1, pos.y + 2) == 1 then
            decoratives[#decoratives + 1] = {
                name = 'rock-small',
                position = pos,
                amount = math_random(1, 1 + math.ceil(20 - y / 2))
            }
        end
        if math_random(1, pos.y + 2) == 1 then
            decoratives[#decoratives + 1] = {
                name = 'rock-tiny',
                position = pos,
                amount = math_random(1, 1 + math.ceil(20 - y / 2))
            }
        end
    end

    for _, e in pairs(
        surface.find_entities_filtered({area = {{top_x, top_y}, {top_x + 32, top_y + 32}}, type = 'cliff'})
    ) do
        e.destroy()
    end
end

local function biter_chunk(data)
    local surface = data.surface
    local entities = data.entities
    local tile_positions = {}
    local x, y = Public.increment_value(data)

    local p = {x = x + data.top_x, y = y + data.top_y}
    tile_positions[#tile_positions + 1] = p

    local disable_spawners = {
        callback = Functions.deactivate_callback
    }
    local disable_worms = {
        callback = Functions.active_not_destructible_callback
    }

    if math.random(1, 128) == 1 then
        local position =
            surface.find_non_colliding_position('biter-spawner', tile_positions[math_random(1, #tile_positions)], 16, 2)
        if position then
            entities[#entities + 1] = {
                name = spawner_raffle[math_random(1, #spawner_raffle)],
                position = position,
                force = 'enemy',
                callback = disable_spawners
            }
        end
    end

    if math.random(1, 128) == 1 then
        local position =
            surface.find_non_colliding_position(
            'big-worm-turret',
            tile_positions[math_random(1, #tile_positions)],
            16,
            2
        )
        if position then
            entities[#entities + 1] = {
                name = 'big-worm-turret',
                position = position,
                force = 'enemy',
                callback = disable_worms
            }
        end
    end
end

local function out_of_map(x, y, data)
    local tiles = data.tiles

    local p = {x = x, y = y}

    tiles[#tiles + 1] = {name = 'out-of-map', position = p}
end

function Public.heavy_functions(x, y, data)
    local top_x = data.top_x
    local top_y = data.top_y
    local surface = data.surface
    local p = {x = data.x, y = data.y}
    local oom = surface.get_tile(p).name == 'out-of-map'

    local map_name = 'mountain_fortress_v3'

    if string.sub(surface.name, 0, #map_name) ~= map_name then
        return
    end

    if not data.seed then
        data.seed = data.surface.map_gen_settings.seed
    end
    if oom then
        return
    end

    if top_y % Public.level_depth == 0 and top_y < 0 then
        WPT.get().left_top = data.left_top
        wall(data)
        return
    end

    if top_y == -128 and top_x == -128 then
        local pl = WPT.get().locomotive.position
        for _, entity in pairs(
            surface.find_entities_filtered(
                {area = {{pl.x - 5, pl.y - 6}, {pl.x + 5, pl.y + 10}}, type = 'simple-entity'}
            )
        ) do
            entity.destroy()
        end
    end

    if top_y < 0 then
        process_bits(x, y, data)
        place_wagon(x, y, data)
        return
    end

    if top_y > 120 then
        out_of_map(x, y, data)
        return
    end

    if top_y > 75 then
        biter_chunk(data)
        return
    end

    if top_y >= 0 then
        border_chunk(data)
        return
    end
end

Event.add(
    defines.events.on_chunk_generated,
    function(e)
        local surface = e.surface
        local map_name = 'mountain_fortress_v3'

        if string.sub(surface.name, 0, #map_name) ~= map_name then
            return
        end

        local area = e.area
        local left_top = area.left_top
        if not surface then
            return
        end
        if not surface.valid then
            return
        end

        if left_top.y > 32 then
            game.forces.player.chart(surface, {{left_top.x, left_top.y}, {left_top.x + 31, left_top.y + 31}})
        end
    end
)

return Public
