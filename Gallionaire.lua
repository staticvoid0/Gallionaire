--[[ 
Copyright © 2025, Staticvoid
All rights reserved.
Redistribution and use in source and binary forms, without
modification, is permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Gallionaire nor the
      name of its author may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Staticvoid BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**THANKS AND CREDIT TO SETH VAN HEULEN FOR THE NPC DATA



]] --[[
    Gallimaufry Tracker addon for Windower 4
    Tracks gallimaufry earned in Sortie per instance, record per instance and total held and displays it on screen
    with messages and sound effects at gallimaufry thresholds; Tracks and displays Ruspix plate and shiny plate timers. Shows the status of
	temp-items within sortie such as shards, metals, fragments and the seal. Opens doors by targetting them (No need to drop invisible) with 
	an option to toggle auto-open when approaching the doors. Tracks NPCs within Sortie and displays their location. Displays an Absorb-TP readout 
	when fighting Aminon. Shows "Gallionaire" in blue ordinarily, but displays it in green while in a sortie zone or sortie staging zone and all 
	6 party members are within 15 yalms, providing an indicator for when it is safe to pull bosses without having to count 6 players.
    More to come!
]] 


_addon.name = 'Gallionaire'
_addon.author = 'Staticvoid'
_addon.version = '2.5'
_addon.commands = {'Gallionaire', 'ga'}

require('tables')

require('chat')

require('logger')

require('functions')

require('strings')

require('luau')

packets = require('packets')

config = require('config')

res = require('resources')

local texts = require('texts')

bit = require('bit')

require('pack')

local player_name = windower.ffxi.get_info().logged_in and windower.ffxi.get_player().name
local addon_path = windower.addon_path
local screen_w = windower.get_windower_settings().ui_x_res
local screen_h = windower.get_windower_settings().ui_y_res
local interaction_delay = 0
local player_total = 0
local galli_message_id = 39998
local last_update_time = 0
local update_interval = 5
local initial_delay = 60
local refresh_interval = 60
local manual_time_checker = 0
local ruspix_updatinator = os.clock()
local current_character = nil
local frame_count = 0
local npc_status = {}
local defaults = {}
local last = {}
local doors = S{}
local thresholds = {10000, 20000, 30000, 40000, 50000, 60000}
local last_threshold = 0
local zone_in_amount = nil
local last_zone_time = nil
local oh_notifier = {}
local absorb_counts = {}
local flags = {}
local plates = {}
plates.shiny = {}
plates.shiny.timer = nil
plates.shiny.start_time = 153223
plates.shiny.duration = 20 * 60 * 60
plates.shiny.cooldown_seconds = 20 * 60 * 60
plates.ruspix = {}
plates.ruspix.accumulation_rate = 5
plates.ruspix.start_time = 0
plates.ruspix.manually_entered = 0
plates.ruspix.accumulated_time = 0
plates.ruspix.grabbed_ruspix_plate = true
flags.entered_sortie = true
flags.entered_sortie_now = false
flags.zoning = false
flags.in_sortie_zone = false
flags.polling_zone = false
flags.in_leafalia = false
flags.in_silverknife = false
flags.upgraded_weapon = false

-- Display settings
local settings = config.load('data/settings_' .. player_name .. '.xml', {
    pos = {
        x = screen_w / 5,
        y = screen_h / 10000
    },
    bg = {
        alpha = 150,
        red = 0,
        green = 0,
        blue = 40
    },
    text = {
        size = 10,
        font = 'Comic Sans MS',
        red = 255,
        green = 255,
        blue = 255,
        alpha = 255,
        stroke = {
            alpha = 255,
            red = 15,
            green = 15,
            blue = 15,
            width = 2,
            padding = 1
        }
    },
	padding = 1,
    gallimaufry_record = 0,
	plates = {
	shiny = {
    start_time = 0,
	},
	ruspix = {
	accumulated_time = 0,
	start_time = 0,
	},
},
	toggle_sound = true,
	Auto = true,
    Range = 10,
})
local gallimaufry_record = settings.gallimaufry_record
-- UI elements
local display = texts.new('', settings, settings)

local sortie_display = texts.new(config.load{
	pos = {
        x = math.floor(screen_w / 1.1199),
        y = math.floor(screen_h / 5),
    },
    bg = {
        alpha = 125,
        red = 0,
        green = 0,
        blue = 40
    },
    flags = {
        bold = true,
    },
    text = {
        size = 9,
        font = 'Comic Sans MS',
        red = 190,
        green = 210,
        blue = 253,
        alpha = 255,
        stroke = {
            alpha = 255,
            red = 15,
            green = 15,
            blue = 15,
            width = 3,
            padding = 2
        }
    },
})

local aminon_display = texts.new(config.load('data/absorb_settings.xml', {
	pos = {
        x = math.floor(screen_w / 8),
        y = math.floor(screen_h / 6),
    },
	bg = {
        alpha = 125,
        red = 0,
        green = 0,
        blue = 40
    },
    text = {size = 12, font = 'Consolas', stroke = {alpha = 255,width = 3,padding = 2
        }},
}))

local sound_paths = {
    outstanding = addon_path .. 'data/waves/30.wav',
    a_minor = addon_path .. 'data/waves/a_minor.wav',
	loading = addon_path .. 'data/waves/load.wav',
	notify = addon_path .. 'data/waves/notify.wav',
	warning = addon_path .. 'data/waves/warning.wav'
}
   --   NM and bitzer machinery
------------------------------------------------------------------------
local map_location = {
    [0] = {
        ['(A-1)'] = 'Vamp. rm',
    },
    [1] = {
        ['(F-6)'] = 'Gadget #A',
        ['(F-7)'] = 'Big rm #A boss',
        ['(G-7)'] = 'Big rm #A boss',
        ['(H-7)'] = 'NW of Dev. #A',
        ['(I-7)'] = 'NW of Dev. #A',
        ['(J-7)'] = 'NW of Dev. #A',
        ['(K-7)'] = 'NW of Dev. #A',
        ['(F-8)'] = 'Big rm #A boss',
        ['(G-8)'] = 'Big rm #A boss',
        ['(H-8)'] = 'NW of Dev. #A',
        ['(I-8)'] = 'NW of Dev. #A',
        ['(J-8)'] = 'NW of Dev. #A',
        ['(F-9)'] = 'Big rm #A boss',
        ['(G-9)'] = 'Big rm #A boss',
        ['(I-9)'] = 'NW of Dev. #A',
        ['(J-9)'] = 'NW of Dev. #A',
    },
    [2] = {
        ['(F-6)'] = 'Big rm NE-N Dev. #A',
        ['(G-6)'] = 'Big rm NE-N Dev. #A',
        ['(H-6)'] = 'Big rm NE-N Dev. #A',
        ['(I-6)'] = 'Big rm NE-N Dev. #A',
        ['(F-7)'] = 'Big rm NE-N Dev. #A',
        ['(G-7)'] = 'Big rm NE-N Dev. #A',
        ['(H-7)'] = 'NE Dev. #A',
        ['(I-7)'] = 'NE Dev. #A',
        ['(J-7)'] = 'NE Dev. #A',
        ['(G-8)'] = 'Small rm NE Dev. #A',
        ['(H-8)'] = 'NE Dev. #A',
        ['(I-8)'] = 'NE Dev. #A',
        ['(J-8)'] = 'NE Dev. #A',
        ['(F-9)'] = 'Dev. #A',
        ['(G-9)'] = 'Small rm NE Dev. #A',
        ['(H-9)'] = 'Small rm NE Dev. #A',
        ['(F-10)'] = 'Dev. #A',
        ['(G-10)'] = 'Dev. #A',
        ['(H-10)'] = 'Dev. #A',
    },
    [3] = {
        ['(I-5)'] = 'Big rm #B boss',
        ['(J-5)'] = 'Big rm #B boss',
        ['(G-6)'] = 'Big rm #B boss',
        ['(H-6)'] = 'Big rm #B boss',
        ['(I-6)'] = 'Big rm #B boss',
        ['(G-7)'] = 'Big rm #B boss',
        ['(H-7)'] = 'Big rm #B boss',
        ['(I-7)'] = 'Big rm #B boss',
        ['(H-8)'] = 'S #B boss, NE Dev. #B',
        ['(I-8)'] = 'S #B boss, NE Dev. #B',
        ['(E-9)'] = 'Med. rm NE Dev. #B',
        ['(G-9)'] = 'Med. rm NE Dev. #B',
        ['(H-9)'] = 'S #B boss, NE Dev. #B',
        ['(I-9)'] = 'S #B boss, NE Dev. #B',
        ['(E-10)'] = 'Med. rm NE Dev. #B',
        ['(F-10)'] = 'Med. rm NE Dev. #B',
        ['(G-10)'] = 'Med. rm NE Dev. #B',
        ['(H-10)'] = 'Med. rm NE Dev. #B',
        ['(I-10)'] = 'S #B boss, NE Dev. #B',
    },
    [4] = {
        ['(G-5)'] = 'N starting Dev.',
        ['(H-5)'] = 'N starting Dev.',
        ['(I-5)'] = 'N starting Dev.',
        ['(G-6)'] = 'N starting Dev.',
        ['(H-6)'] = 'N starting Dev.',
        ['(I-6)'] = 'N starting Dev.',
        ['(F-7)'] = 'Starting Dev.',
        ['(G-7)'] = 'Starting Dev.',
        ['(H-7)'] = 'Starting Dev.',
        ['(I-7)'] = 'Starting Dev.',
        ['(F-8)'] = 'Starting Dev.',
        ['(G-8)'] = 'Starting Dev.',
        ['(H-8)'] = 'Starting Dev.',
        ['(I-8)'] = 'Starting Dev.',
        ['(G-9)'] = 'S starting Dev.',
        ['(H-9)'] = 'S starting Dev.',
        ['(G-10)'] = 'S starting Dev.',
        ['(H-10)'] = 'S starting Dev.',
    },
    [5] = {
        ['(I-5)'] = 'Med. rm NW Dev. #A',
        ['(G-6)'] = 'Med. rm NW Dev. #A',
        ['(H-6)'] = 'Med. rm NW Dev. #A',
        ['(I-6)'] = 'Med. rm NW Dev. #A',
        ['(H-7)'] = 'Med. rm NW Dev. #A',
        ['(I-7)'] = 'Med. rm NW Dev. #A',
        ['(F-8)'] = 'Small rm NW Dev. #D',
        ['(G-8)'] = 'Small rm NW Dev. #D',
        ['(H-8)'] = 'Small rm NW Dev. #D',
        ['(F-9)'] = 'Small rm NW Dev. #D',
        ['(G-9)'] = 'Small rm NW Dev. #D',
        ['(H-9)'] = 'Dev. #D',
        ['(G-10)'] = 'Dev. #D',
        ['(H-10)'] = 'Dev. #D',
    },
    [6] = {
        ['(G-6)'] = 'N #C boss, SE Dev. #B',
        ['(H-6)'] = 'N #C boss, SE Dev. #B',
        ['(I-6)'] = 'N #C boss, SE Dev. #B',
        ['(G-7)'] = 'N #C boss, SE Dev. #B',
        ['(H-7)'] = 'N #C boss, SE Dev. #B',
        ['(I-7)'] = 'N #C boss, SE Dev. #B',
        ['(J-7)'] = 'Big rm #C boss',
        ['(F-8)'] = 'W #C boss, SE Dev. #C',
        ['(G-8)'] = 'W #C boss, SE Dev. #C',
        ['(H-8)'] = 'Big rm #C boss',
        ['(I-8)'] = 'Big rm #C boss',
        ['(J-8)'] = 'Big rm #C boss',
        ['(E-9)'] = 'W #C boss, SE Dev. #C',
        ['(F-9)'] = 'W #C boss, SE Dev. #C',
        ['(G-9)'] = 'W #C boss, SE Dev. #C',
        ['(H-9)'] = 'W #C boss, SE Dev. #C',
        ['(I-9)'] = 'Big rm #C boss',
        ['(J-9)'] = 'Big rm #C boss',
        ['(E-10)'] = 'W #C boss, SE Dev. #C',
        ['(F-10)'] = 'W #C boss, SE Dev. #C',
        ['(G-10)'] = 'W #C boss, SE Dev. #C',
        ['(H-10)'] = 'W #C boss, SE Dev. #C',
        ['(I-10)'] = 'Big rm #C boss',
        ['(J-10)'] = 'Big rm #C boss',
    },
    [7] = {
        ['(G-6)'] = 'Big rm #D boss',
        ['(H-6)'] = 'Big rm #D boss',
        ['(G-7)'] = 'Big rm #D boss',
        ['(H-7)'] = 'Big rm #D boss',
        ['(I-7)'] = 'Big rm #D boss',
        ['(G-8)'] = 'Big rm #D boss',
        ['(H-8)'] = 'Big rm #D boss',
        ['(I-8)'] = 'Big rm #D boss',
        ['(G-9)'] = 'Big rm #D boss',
        ['(H-9)'] = 'Big rm #D boss',
        ['(I-9)'] = 'Big rm #D boss',
    },
    [8] = {
        ['(F-5)'] = 'Med. rm SW Dev. #D',
        ['(G-5)'] = 'Med. rm SW Dev. #D',
        ['(F-6)'] = 'Med. rm SW Dev. #D',
        ['(G-6)'] = 'Med. rm SW Dev. #D',
        ['(H-6)'] = 'Med. rm SW Dev. #D',
        ['(F-7)'] = 'Med. rm SW Dev. #D',
        ['(H-7)'] = 'Small rm SW Dev. #C',
        ['(I-7)'] = 'Small rm SW Dev. #C',
        ['(G-8)'] = 'SW Dev. #C',
        ['(H-8)'] = 'SW Dev. #C',
        ['(I-8)'] = 'Small rm SW Dev. #C',
        ['(G-9)'] = 'SW Dev. #C',
        ['(H-9)'] = 'SW Dev. #C',
        ['(I-9)'] = 'Big rm SW-S Dev. #C',
        ['(J-9)'] = 'Big rm SW-S Dev. #C',
        ['(G-10)'] = 'SW Dev. #C',
        ['(H-10)'] = 'SW Dev. #C',
        ['(I-10)'] = 'Big rm SW-S Dev. #C',
        ['(J-10)'] = 'Big rm SW-S Dev. #C',
    },
    [9] = {
        ['(G-6)'] = 'Dev. #B',
        ['(H-6)'] = 'Dev. #B',
        ['(F-7)'] = 'Dev. #C',
        ['(G-7)'] = 'Sm. rm SE Dev. #B',
        ['(H-7)'] = 'Sm. rm SE Dev. #B',
        ['(I-7)'] = 'Sm. rm SE Dev. #B',
        ['(J-7)'] = 'Sm. rm SE Dev. #B',
        ['(F-8)'] = 'Dev. #C',
        ['(G-8)'] = 'Med. rm SE Dev. #C',
        ['(H-8)'] = 'Med. rm SE Dev. #C',
        ['(I-8)'] = 'Sm. rm SE Dev. #B',
        ['(F-9)'] = 'Med. rm SE Dev. #C',
        ['(G-9)'] = 'Med. rm SE Dev. #C',
        ['(H-9)'] = 'Med. rm SE Dev. #C',
        ['(F-10)'] = 'Med. rm SE Dev. #C',
        ['(G-10)'] = 'Med. rm SE Dev. #C',
        ['(H-10)'] = 'Med. rm SE Dev. #C',
    },
    [10] = {
        ['(F-6)'] = 'Gadget #E',
        ['(G-6)'] = 'Gadget #E',
        ['(F-7)'] = '#E boss, NW corner',
        ['(G-7)'] = '#E boss, NE corner',
        ['(H-7)'] = 'Split-rm, 1st 1/2',
        ['(I-7)'] = 'Split-rm, 1st 1/2',
        ['(J-7)'] = 'Starting rm',
        ['(F-8)'] = '#E boss, SW corner',
        ['(G-8)'] = '#E boss, SE corner',
        ['(H-8)'] = 'Split-rm',
        ['(I-8)'] = 'Split-rm',
        ['(J-8)'] = 'Starting rm',
        ['(K-8)'] = 'Starting rm',
        ['(F-9)'] = 'Big flan rm',
        ['(G-9)'] = 'Big flan rm',
        ['(J-9)'] = 'Starting rm',
        ['(E-10)'] = 'Big flan rm',
        ['(F-10)'] = 'Big flan rm',
        ['(G-10)'] = 'Big flan rm',
    },
    [11] = {
        ['(F-7)'] = 'Far, NW corner',
        ['(G-7)'] = 'Far, N hallway',
        ['(H-7)'] = 'Far, NE corner',
        ['(F-8)'] = 'Far, SW corner',
        ['(G-8)'] = 'Far, S hallway',
        ['(H-8)'] = 'Far, SE corner',
        ['(I-8)'] = 'Big pixie rm',
        ['(J-8)'] = 'Big pixie rm',
    },
    [12] = {
        ['(F-7)'] = '#F boss, NW corner',
        ['(G-7)'] = '#F boss, N hallway',
        ['(H-7)'] = '#F boss, NE corner',
        ['(I-7)'] = 'Gadget #F',
        ['(F-8)'] = '#F boss, SW corner',
        ['(G-8)'] = '#F boss, S hallway',
        ['(H-8)'] = '#F boss, SE corner',
        ['(I-8)'] = 'OffPath, N hallway',
        ['(J-8)'] = 'OffPath, NE corner',
        ['(F-9)'] = 'Split-rm second half',
        ['(G-9)'] = 'Split-rm',
        ['(H-9)'] = 'OffPath, SW corner',
        ['(I-9)'] = 'OffPath, S hallway',
        ['(J-9)'] = 'OffPath, SE corner',
    },
    [13] = {
        ['(I-6)'] = 'Start rm',
        ['(H-7)'] = 'Start rm',
        ['(I-7)'] = 'Start rm',
        ['(J-7)'] = 'Start rm',
        ['(F-8)'] = 'OffPath, NW corner',
        ['(G-8)'] = 'OffPath, NE corner',
        ['(H-8)'] = 'Split-rm, 1st 1/2',
        ['(I-8)'] = 'Split-rm',
        ['(F-9)'] = 'OffPath, W hallway',
        ['(G-9)'] = 'OffPath, E hallway',
        ['(H-9)'] = 'Split-rm, 1st 1/2',
        ['(I-9)'] = 'Split-rm',
        ['(F-10)'] = 'OffPath, SW corner',
        ['(G-10)'] = 'OffPath, SE corner',
    },
    [14] = {
        ['(I-6)'] = 'Start rm',
        ['(H-7)'] = 'Start rm',
        ['(I-7)'] = 'Start rm',
        ['(J-7)'] = 'Start rm',
        ['(G-8)'] = 'Start rm',
        ['(H-8)'] = 'Start rm',
        ['(I-8)'] = 'Start rm',
        ['(F-9)'] = 'Start rm',
        ['(G-9)'] = 'Start rm',
        ['(H-9)'] = 'Split-rm',
        ['(I-9)'] = 'Split-rm',
        ['(J-9)'] = 'Split-rm',
        ['(G-10)'] = 'Starting rm',
        ['(H-10)'] = 'Split-rm, 1st 1/2',
        ['(I-10)'] = 'Split-rm, 1st 1/2',
    },
    [15] = {
        ['(F-7)'] = '#H boss, NW corner',
        ['(G-7)'] = '#H boss, NE corner',
        ['(F-8)'] = '#H boss, W hallway',
        ['(G-8)'] = '#H boss, SE corner',
        ['(H-8)'] = 'Big fomor rm',
        ['(I-8)'] = 'Big fomor rm',
        ['(J-8)'] = 'Far, NW corner',
        ['(K-8)'] = 'Far, NE corner',
        ['(F-9)'] = '#H boss, SW corner',
        ['(G-9)'] = '#H boss, SE corner',
        ['(H-9)'] = 'Big fomor rm',
        ['(I-9)'] = 'Big fomor rm',
        ['(J-9)'] = 'Far, SW corner',
        ['(K-9)'] = 'Far, SE corner',
    },
    [16] = {
        ['(G-7)'] = '#G boss, NW corner',
        ['(H-7)'] = '#G boss, N hallway',
        ['(I-7)'] = '#G boss, NE corner',
        ['(G-8)'] = '#G boss, SW corner',
        ['(H-8)'] = '#G boss, S hallway',
        ['(I-8)'] = '#G boss, SE corner',
    },
}

local tracked_zone = {
    [133] = "Outer Ra'Kaznar [U2]",
    [189] = "Outer Ra'Kaznar [U3]",
    [275] = "Outer Ra'Kaznar [U1]",
}

local tracked_npc = {
    [0x0090] = 'Obdella',
    [0x00df] = 'Porxie',
    [0x011d] = 'Bhoot',
    [0x0175] = 'Deleterious',
    [0x01ab] = 'Botulus',
    [0x01f2] = 'Ixion',
    [0x0228] = 'Naraka',
    [0x026e] = 'Tulittia',
    [0x0345] = 'Bitzer #E',
    [0x0346] = 'Bitzer #F',
    [0x0347] = 'Bitzer #G',
    [0x0348] = 'Bitzer #H',
}

local sectors = {
    {name='A',npcs={0x0090}},
    {name='B',npcs={0x00df}},
    {name='C',npcs={0x011d}},
    {name='D',npcs={0x0175}},
    {name='E',npcs={0x01ab,0x0345}},
    {name='F',npcs={0x01f2,0x0346}},
    {name='G',npcs={0x0228,0x0347}},
    {name='H',npcs={0x026e,0x0348}},
}

function initialization()
    start_up = true
    initial_checkthrough = false
    previous_gallimaufry = 0
    earned_gallimaufry = 0
    newly_earned_gallimaufry = 0
    coroutine.schedule(induct_data, 0.5)
end

function induct_data()
    if not windower.ffxi.get_info().logged_in then
        return
    end
    local packet = packets.new('outgoing', 0x115, {})
    packets.inject(packet)
end

initialization()

windower.register_event('incoming chunk', function(id, org, modi, is_injected, is_blocked)
    local player = windower.ffxi.get_player()
    if is_injected or id ~= 0x118 then
        return
    end
    local current_time = os.clock()
    if current_time - last_update_time < update_interval then
        return
    end

    local p = packets.parse('incoming', org)
    local new_gallimaufry = p["Gallimaufry"]

    if start_up then
        previous_gallimaufry = new_gallimaufry
        start_up = false
    elseif new_gallimaufry ~= previous_gallimaufry then
       if player and player.name == current_character then 
		    earned_gallimaufry = earned_gallimaufry + (new_gallimaufry - previous_gallimaufry)
       else
            earned_gallimaufry = 0
	   end
        previous_gallimaufry = new_gallimaufry
        update_display()
    end
    last_update_time = current_time
end)

windower.register_event('incoming chunk', function(id, data)
    if flags.in_sortie_zone then
        -- Parse the packet to log relevant information
        local packet = packets.parse('incoming', data)
        if id == 0x02A and not injected then
            --windower.add_to_chat(207,
                --string.format('Packet 0x02A - Message ID: %d, Param 1: %d, Param 2: %d', packet['Message ID'],
                    --packet['Param 1'], packet['Param 2']))
            if initial_checkthrough == true and not galli_message_id then
                --print("Initial checkthrough data induction")
                induct_data()
            end
            -- Only process if Param 1 and Param 2 exist
            if packet['Param 2'] and packet['Param 1'] then
                if galli_message_id and packet['Message ID'] == galli_message_id and previous_gallimaufry ~= packet['Param 2'] then
                    -- Handle potential loss of packets
                    --print(galli_message_id)
                    --if packet['Param 2'] - packet['Param 1'] ~= player_total and player_total ~= 0 then
                        --earned_gallimaufry = earned_gallimaufry + (packet['Param 2'] - player_total)
						--print("Debugging message, Packetloss detected; attempting to correct")
                        --windower.add_to_chat(207, 'Gallimaufry updated with adjustment: ' .. earned_gallimaufry)
                    --else
                        --earned_gallimaufry = earned_gallimaufry + packet['Param 1']
                        --windower.add_to_chat(207, 'Gallimaufry updated: ' .. earned_gallimaufry)
                    --end
                    -- Update player total
                    --player_total = packet['Param 2']
						if zone_in_amount then
							previous_gallimaufry = packet['Param 2']
							earned_gallimaufry = packet['Param 2'] - zone_in_amount
						else
							zone_in_amount = previous_gallimaufry
							previous_gallimaufry = packet['Param 2']
							earned_gallimaufry = packet['Param 2'] - zone_in_amount
						end
				elseif galli_message_id and packet['Message ID'] ~= galli_message_id and packet['Param 2'] == previous_gallimaufry + packet['Param 1'] then
					-- This should indicate SE has added something to the currency 2 menu and we'll need to grab the new Message ID dynamically until this addon receives an update.
					--print("Packet Message ID updated Dynamically")
					galli_message_id = packet['Message ID']
                elseif not galli_message_id then

                    if packet['Param 2'] == previous_gallimaufry + packet['Param 1'] then
                        galli_message_id = packet['Message ID'] -- Store the dynamic message ID
                        --windower.add_to_chat(207, 'Galli message ID dynamically updated to: ' .. galli_message_id)
                    else
                        initial_checkthrough = true
                    end
                end
                update_display()
            end
        end
    elseif flags.in_silverknife then
        if id == 0x034 then
            flags.upgraded_weapon = true
            --induct_data()
        end
    end
---------------------------------------------------------------------------
end)
windower.register_event('incoming chunk', function(id, original)
    if not tracked_zone[windower.ffxi.get_info().zone] then return end
    if id == 0x00E then
        local index = original:unpack('H', 9)
        if not tracked_npc[index] then return end
        local mask = original:byte(11)
        if bit.band(mask, 1) == 1 then
            local x, z, y = original:unpack('fff', 13)
            npc_status[index] = npc_status[index] or {}
            npc_status[index].map = windower.ffxi.get_map_data(x, y, z)
            npc_status[index].position = windower.ffxi.get_position(x, y, z)
        end
        if bit.band(mask, 4) == 4 then
            npc_status[index] = npc_status[index] or {}
            npc_status[index].hidden = bit.band(original:byte(33), 6) ~=0
            npc_status[index].dead = original:byte(32) > 1
        end
        update_sortie_display()
        if npc_status[index] and npc_status[index].wait_ping then
            npc_status[index].wait_ping = nil
            return true
        end
    end
    if id == 0x065 then
        next_refresh = 0
    end
end)
function display_message(earned_gallimaufry)

        if earned_gallimaufry >= 78000 and last_threshold < 78000 then
            windower.add_to_chat(207, "Aminon: Outstanding!")
			last_threshold = 78000
			aminon_display:hide()
		    if toggle_sound then
                windower.play_sound(sound_paths.outstanding)
			end
        elseif earned_gallimaufry >= 48000 and last_threshold < 48000 then
            windower.add_to_chat(207, "Aminon: Impressive!")
            last_threshold = 48000
			if toggle_sound then
                windower.play_sound(sound_paths.a_minor)
			end
        elseif earned_gallimaufry >= 40000 and last_threshold < 40000 then
		    windower.add_to_chat(200, "40,000 gallimaufry.")
            last_threshold = 40000
        elseif earned_gallimaufry >= 30000 and last_threshold < 30000 then
		    windower.add_to_chat(200, "30,000 gallimaufry.")
            last_threshold = 30000
        elseif earned_gallimaufry >= 20000 and last_threshold < 20000 then
            windower.add_to_chat(200, "20,000 gallimaufry.")
            last_threshold = 20000
        elseif earned_gallimaufry >= 10000 and last_threshold < 10000 then
            windower.add_to_chat(200, "10,000 gallimaufry")
            last_threshold = 10000
        end
end

update_doors = function()
    local mobs = windower.ffxi.get_mob_array()
    doors:clear()
    for index, mob in pairs(mobs) do
        if mob.spawn_type == 34 and mob.distance < 2500 then
            doors:add(index)
        end
    end
end:cond(function()
    return settings.Auto
end)

update_doors()

exceptions = S{
    17097337,
}

check_door = function(door)
	return door
        and door.spawn_type == 34
        and door.distance < settings.Range^2
        and (not last[door.index] or os.time() - last[door.index] > 7)
        and door.name:byte() ~= 95
        and door.name ~= 'Furniture'
        and not exceptions:contains(door.id)
		and door.status == 9
end

-- Function to interpolate between colors
local function interpolate_color(start_color, end_color, fraction)
    local red = start_color.red + (end_color.red - start_color.red) * fraction
    local green = start_color.green + (end_color.green - start_color.green) * fraction
    local blue = start_color.blue + (end_color.blue - start_color.blue) * fraction
    return {
        red = red,
        green = green,
        blue = blue
    }
end

-- Function to determine the interpolated color based on gallimaufry count
local function determine_color(gallimaufry)
    local thresholds = {
	{
        value = 0,
        color = {
            red = 255,
            green = 0,
            blue = 0
        }
    }, -- Red
    {
        value = 20000,
        color = {
            red = 225,
            green = 165,
            blue = 0
        }
    }, -- Orange
    {
        value = 30000,
        color = {
            red = 255,
            green = 255,
            blue = 0
        }
    }, -- Yellow
    {
        value = 40000,
        color = {
            red = 0,
            green = 255,
            blue = 0
        }
    }, -- Green
    {
        value = 50000,
        color = {
            red = 0,
            green = 0,
            blue = 255
        }
    }, -- Blue
    {
        value = 60000,
        color = {
            red = 140,
            green = 0,
            blue = 140
        }
    } -- Purple
}

    for i = 1, #thresholds - 1 do
        local current = thresholds[i]
        local next = thresholds[i + 1]

        if gallimaufry >= current.value and gallimaufry < next.value then
            local fraction = (gallimaufry - current.value) / (next.value - current.value)
            return interpolate_color(current.color, next.color, fraction)
        end
    end

    -- If gallimaufry goes further we maintain the last color (purple)
    return thresholds[#thresholds].color
end

function format_with_commas(amount)
    local formatted = tostring(amount):reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return formatted:sub(1, 1) == "," and formatted:sub(2) or formatted
end

local shard_metal_ids = {
    A = {
        shard = 9906,
        metal = 9918
    },
    B = {
        shard = 9907,
        metal = 9919
    },
    C = {
        shard = 9908,
        metal = 9920
    },
    D = {
        shard = 9909,
        metal = 9921
    },
    E = {
        shard = 9910,
        metal = 9922
    },
    F = {
        shard = 9911,
        metal = 9923
    },
    G = {
        shard = 9912,
        metal = 9924
    },
    H = {
        shard = 9913,
        metal = 9925
    }
}

function has_ruspix_plate()
    local key_items = windower.ffxi.get_key_items()
    for _, ki in ipairs(key_items) do
        if ki == 3300 then
            return true
        end
    end
    return false
end

local function has_item(item_id)
    local temp_items = windower.ffxi.get_items(3)
    for _, item in ipairs(temp_items) do
        if item.id == item_id then
            return true
        end
    end
    return false
end

-- Function to generate the display string for the shards and metals
local function get_sector_display()
    local display_str = ""
    local displayed_keys = {"A", "B", "C", "D", "E", "F", "G", "H"}
    
    for _, sector in ipairs(displayed_keys) do
        local ids = shard_metal_ids[sector]
        local shard_color = has_item(ids.shard) and "\\cs(0,255,0)√\\cr" or " "
        local metal_color = has_item(ids.metal) and "\\cs(0,255,0)√\\cr" or " "

        display_str = display_str .. sector .. ":" .. shard_color .. "," .. metal_color .. "|"
    end
    return display_str
end

local function start_shinyplate_timer()
	
	plates.shiny.start_time = os.time() -- Get the current real-world time
    plates.shiny.timer = plates.shiny.duration - (os.time() - plates.shiny.start_time)
	plates.ruspix.start_time = (plates.shiny.start_time) + (plates.shiny.duration) -- Start Ruspix accumulation after 20 hours
	settings.plates.ruspix.start_time = plates.ruspix.start_time
    settings.plates.shiny.start_time = plates.shiny.start_time -- Save the start time to settings.xml
    settings:save()
end

local function load_timer_from_settings()
    if not settings then
        log('Settings table is nil. Retrying...')
        coroutine.sleep(1) -- Retry delay
        return load_timer_from_settings()
    end
    if settings.plates.shiny.start_time then
        plates.shiny.start_time = settings.plates.shiny.start_time
    else
        coroutine.sleep(1)  -- Small delay to retry loading
		log('No shinyplayte_start_time found in settings.xml for '..player_name)
        plates.shiny.start_time = settings.plates.shiny.start_time
    end
    plates.ruspix.start_time = settings.plates.ruspix.start_time 
    plates.ruspix.accumulated_time = settings.plates.ruspix.accumulated_time 
	coroutine.sleep(0.4)
	update_display()
	plates.shiny.timer = plates.shiny.duration - (os.time() - plates.shiny.start_time)
end

local function save_ruspix_data()
		if  plates.ruspix.accumulated_time ~= settings.plates.ruspix.accumulated_time then
		    settings.plates.ruspix.accumulated_time = plates.ruspix.accumulated_time
			settings.plates.ruspix.start_time = os.time()
		    settings:save()
			--settings:save()
		end
end

-- Check to see if the bard's recast on 1hrs is low enough or the cor has used cutting cards.
local function one_hour_checker()
	local player = windower.ffxi.get_player()
	if player.main_job ~= 'COR' and player.main_job ~= 'BRD' then return end
	local abil_recasts = windower.ffxi.get_ability_recasts()[254] / 60
	if player.main_job == 'COR' then
		if abil_recasts == 0 then
			log("Cut the bard...")
			coroutine.sleep(1)
			log("Cut the bard...")
			if toggle_sound then windower.play_sound(sound_paths.notify) end
		end
	elseif player.main_job == 'BRD' then
		if abil_recasts > 0 then
			if abil_recasts > 33.75 then
				log("Ask for cutting cards...")
				coroutine.sleep(1)
				log("Ask for cutting cards...")
				if toggle_sound then windower.play_sound(sound_paths.notify) end
			elseif oh_notifier.five and abil_recasts > 23 then
				log("Ask for cutting cards...")
				coroutine.sleep(1)
				log("Ask for cutting cards...")
				if toggle_sound then windower.play_sound(sound_paths.notify) end
			elseif oh_notifier.six and abil_recasts > 17 then
				log("Ask for cutting cards...")
				coroutine.sleep(1)
				log("Ask for cutting cards...")
				if toggle_sound then windower.play_sound(sound_paths.notify) end
			end
		end
	end
end

local function vicinity_reader()
    local party = windower.ffxi.get_party()
    if not party then return false end

    local count = 0
    for i = 0, 5 do
        local member = party['p' .. i]
        if member and member.mob then
            local mob = member.mob
            if mob.valid_target and math.sqrt(mob.distance) < 15 then
                count = count + 1
                if count >= 6 then
                    return true
                end
            end
        end
    end
    return false
end

local function get_gallionaire_logo() 
    local primary_color
    local highlight_color
	if flags.polling_zone and not flags.zoning then
		if not vicinity_reader() then 
			primary_color = {red = 0, green = 0, blue = 255} 
			highlight_color = {red = 0, green = 0, blue = 255}
		else
			primary_color = {red = 187, green = 255, blue = 0} 
			highlight_color = {red = 187, green = 255, blue = 0}
		end
	else
			primary_color = {red = 0, green = 0, blue = 255} 
			highlight_color = {red = 0, green = 0, blue = 255}
	end
    local logo_str = string.format(
        '\\cs(%d,%d,%d)Galli\\cr\\cs(%d,%d,%d)onaire\\cr',
        highlight_color.red, highlight_color.green, highlight_color.blue,
        primary_color.red, primary_color.green, primary_color.blue
    )
    
    return logo_str
end

-- Get a count on sapphires and starstones while in Leafallia to cue a gallimaufry check when reforging gear.
function count_rakaznar_gems()
    local starstone_count = 0
    local sapphire_count = 0
    local bags = {
        'inventory', 'safe', 'safe2', 'storage', 'locker',
        'satchel', 'sack', 'case', 'wardrobe', 'wardrobe2',
        'wardrobe3', 'wardrobe4', 'wardrobe5', 'wardrobe6',
        'wardrobe7', 'wardrobe8'
    }
    for _, bag_name in ipairs(bags) do
        local bag_items = windower.ffxi.get_items(bag_name)
        if bag_items and bag_items.max > 0 then 
            for _, item in ipairs(bag_items) do
                if item.id == 9928 then
                    starstone_count = starstone_count + item.count
                elseif item.id == 9927 then
                    sapphire_count = sapphire_count + item.count
                end
            end
        end
    end
    return starstone_count + sapphire_count
end

local function update_ruspix_display()
    -- Initialize plates.ruspix.start_time and accumulated time from settings if available
    if settings.plates.ruspix.start_time and settings.plates.ruspix.start_time > 0 then
        plates.ruspix.start_time = settings.plates.ruspix.start_time
    else
        plates.ruspix.start_time = 0 -- Default value if not set
    end

    if settings.plates.ruspix.accumulated_time then
        plates.ruspix.accumulated_time = settings.plates.ruspix.accumulated_time
    else
        plates.ruspix.accumulated_time = 0 -- Default value if not set
    end
	
	--Ruspix settings updator anti-spam operations
    local updatinator_current_time = os.clock()
    local updatinator_elapsed_time = updatinator_current_time - ruspix_updatinator
	
    -- Calculate elapsed time since Ruspix accumulation began
    local elapsed_time = os.time() - plates.ruspix.start_time

    -- Accumulate time at a rate of 1 second for every 5 seconds
    -- Check if plates.ruspix.start_time is valid and in the past
    if os.time() < plates.ruspix.start_time then
	    plates.ruspix.accumulated_time = plates.ruspix.accumulated_time
    else
        local new_accumulated_time = ((elapsed_time) / (plates.ruspix.accumulation_rate))
        -- Add the increment to the accumulated time
        plates.ruspix.accumulated_time = (plates.ruspix.accumulated_time) + (new_accumulated_time)
    end

			
    -- Cap accumulated time at 20 hours (72000 seconds)
    if plates.ruspix.accumulated_time > 72000 then
        plates.ruspix.accumulated_time = 72000
    end

    -- Apply manual setting if needed
    if plates.ruspix.manually_entered > 1 then
        plates.ruspix.accumulated_time = plates.ruspix.manually_entered
        if manual_time_checker ~= plates.ruspix.manually_entered then
            settings.plates.ruspix.accumulated_time = plates.ruspix.accumulated_time
            settings:save()
            manual_time_checker = plates.ruspix.manually_entered
			plates.ruspix.manually_entered = 0
        end
    end
--[[
	if os.time() >= plates.ruspix.start_time then
	   print(true)                                 -------------------------------------Ruspix timer debugging
	else
	   print(false)                            -------------------------------------Ruspix timer debugging
	end
]]

    if updatinator_elapsed_time > 60 then
	   -- print("Updatinator ... engaged!")                        -------------------------------------Ruspix timer debugging
		--print(plates.ruspix.accumulated_time, settings.plates.ruspix.accumulated_time)
    	if  plates.ruspix.accumulated_time ~= settings.plates.ruspix.accumulated_time then
		    settings.plates.ruspix.accumulated_time = plates.ruspix.accumulated_time
			settings.plates.ruspix.start_time = os.time()
		    settings:save()
			--settings:save()
			--print(plates.ruspix.accumulated_time, settings.plates.ruspix.accumulated_time)
		end
		ruspix_updatinator = updatinator_current_time
    end

    -- Calculate hours and minutes of accumulated Ruspix time
    local hours = math.floor(plates.ruspix.accumulated_time / 3600)
    local minutes = math.floor((plates.ruspix.accumulated_time % 3600) / 60)
	local seconds = math.floor((plates.ruspix.accumulated_time % 3600) % 60)
	--print(seconds)                                                       -------------------------------------Ruspix timer debugging
    -- Determine if Ruspix time is sufficient to recharge the Shinyplate
    local shinyplate_remaining = plates.shiny.cooldown_seconds - (os.time() - plates.shiny.start_time)
    local can_recharge = plates.ruspix.accumulated_time >= shinyplate_remaining --[[and shinyplate_remaining > 0]] and not flags.in_sortie_zone

    -- Determine the color based on accumulated time (reversed thresholds from shinyplate)
    local color = {red = 0, green = 60, blue = 210} -- Default medium blue
    if plates.ruspix.accumulated_time >= 72000 then
        color = {red = 187, green = 255, blue = 0} -- Light-blue when fully accumulated (20:00)
    elseif plates.ruspix.accumulated_time >= 36000 then
        color = {red = 160, green = 255, blue = 255} -- Medium blue for mid-accumulation
    end

    -- Return the formatted time string with color
    local time_str = string.format('\\cs(%d,%d,%d)%02d:%02d\\cr', color.red, color.green, color.blue, hours, minutes)

    -- Return the time string and recharge status
    return time_str, can_recharge
end

local function update_shinyplate_display()
	    if not plates.shiny.start_time then
          return ""
		end

		local real_time = os.time()
	    local elapsed_time = real_time - plates.shiny.start_time
		
	    remaining_time = plates.shiny.cooldown_seconds - elapsed_time
	
	    if remaining_time < 0 then
            remaining_time = 0
        end

        local hours = math.floor(remaining_time / 3600)
        local minutes = math.floor((remaining_time % 3600) / 60)
		local seconds = math.floor(remaining_time % 60 )
        local color = {red = 0, green = 60, blue = 210} -- Red by default
        if remaining_time <= 80 * 60 then
            color = {red = 187, green = 255, blue = 0} -- Light-blue when less than 1 hour
        elseif remaining_time <= 10 * 60 * 60 then
            color = {red = 160, green = 255, blue = 255} -- Medium-blue in the middle
        end

        local time_str = string.format('\\cs(%d,%d,%d)%02d:%02d\\cr', color.red, color.green, color.blue, hours, minutes)
		
        return time_str
end

function update_display()
	local time_str = update_shinyplate_display()
	local ruspix_time_str, can_recharge = update_ruspix_display()
	-------------------Cutting cards / SV/CC notifier------------------------------
	    if flags.in_sortie_zone and not flags.zoning then
			if last_zone_time then
			local time_since_entry = (os.time() - last_zone_time) / 60
				if time_since_entry > 30 and not oh_notifier.six then
					oh_notifier.six = true
					one_hour_checker()
				elseif time_since_entry > 24 and not oh_notifier.five then
					oh_notifier.five = true
					one_hour_checker()
				elseif time_since_entry > 18 and not oh_notifier.four then
					oh_notifier.four = true
					one_hour_checker()
				elseif time_since_entry > 16 and not oh_notifier.three then
					oh_notifier.three = true
					one_hour_checker()
				elseif time_since_entry > 14 and not oh_notifier.two then
					oh_notifier.two = true
					one_hour_checker()
				elseif time_since_entry > 12 and not oh_notifier.one then
					oh_notifier.one = true
					one_hour_checker()
				end
			else
				last_zone_time = os.time()
			end
		end
	-------------------------------------------------------------------------------
	if remaining_time <= 0 then
        if not flags.entered_sortie and flags.entered_sortie_now then
            -- you weren't in sortie, and now you are - start the timer.
		    settings.plates.ruspix.accumulated_time = plates.ruspix.accumulated_time
		    settings:save()
            start_shinyplate_timer()
			
        end
	end
		
        flags.entered_sortie = flags.entered_sortie_now
		
	     local grabbed_ruspix_plate_now = has_ruspix_plate()
	if flags.in_leafalia then
        if not plates.ruspix.grabbed_ruspix_plate and grabbed_ruspix_plate_now then
            -- You are in Leafallia and you didn't have shinyplate, and now you do - update Ruspix plate accumulated time.
            plates.ruspix.accumulated_time = plates.ruspix.accumulated_time - remaining_time
	    	plates.shiny.start_time = plates.shiny.start_time - remaining_time
		    plates.shiny.timer = plates.shiny.start_time
			plates.ruspix.start_time = os.time()
		    settings.plates.shiny.start_time = plates.shiny.start_time
			settings.plates.ruspix.accumulated_time = plates.ruspix.accumulated_time
			settings.plates.ruspix.start_time = plates.ruspix.start_time
			settings:save()
			coroutine.sleep(2)
			windower.send_command('ga reset')
        end
        upgrade_gear_checker = count_rakaznar_gems()
        -- Upgrade Gallimaufry since we have upgraded a piece of gear
	    if upgrade_gear_checker ~= new_upgrade_gear_checker then
	        induct_data()
			coroutine.schedule(update_display, 2)
			new_upgrade_gear_checker = upgrade_gear_checker
	    end
	end
			plates.ruspix.grabbed_ruspix_plate = grabbed_ruspix_plate_now
	---------------------------------------------------------------
	--8888888888888888888888888888888888888888888888888888888888888888888888888888888888
	if earned_gallimaufry ~= 0 and earned_gallimaufry < newly_earned_gallimaufry then--8              
	   earned_gallimaufry = newly_earned_gallimaufry                                 --8
	else                                                                             --8
		newly_earned_gallimaufry = earned_gallimaufry                                --8
	end                                                                              --8
    if earned_gallimaufry < 0 then                                                   --8
    earned_gallimaufry = 0                                                           --8
    end	                                                                             --8             
	--8888888888888888888888888888888888888888888888888888888888888888888888888888888888
    if flags.in_silverknife then
        if flags.upgraded_weapon then 
            interaction_delay = interaction_delay + 1
            if interaction_delay > 4 then
                interaction_delay = 0
                flags.upgraded_weapon = false
                induct_data()
            end
        end
    end

	local dot_color = can_recharge and "\\cs(187,255,0)√\\cr" or "\\cs(140,140,140) \\cr"
	local frag_1 = has_item(9914) and "\\cs(187,255,0)√ \\cr" or "\\cs(140,140,140) \\cr"
	local frag_2 = has_item(9915) and "\\cs(187,255,0)√ \\cr" or "\\cs(140,140,140) \\cr"
	local frag_3 = has_item(9916) and "\\cs(187,255,0)√ \\cr" or "\\cs(140,140,140) \\cr"
	local frag_4 = has_item(9917) and "\\cs(187,255,0)√ \\cr" or "\\cs(140,140,140) \\cr"
	local seal = has_item(9926) and "\\cs(187,255,0)√ \\cr" or "\\cs(140,140,140) \\cr"
    -- Determine the color for earned_gallimaufry based on its value
    local color = determine_color(earned_gallimaufry)
	
    -- Format the text with earned_gallimaufry in a specific color
    local shard_metal_display = ""
    
    -- Check if the player is in Sortie zone and append the shard/metal section
	
    if flags.in_sortie_zone == true then
        shard_metal_display = " | Shard/Metal  " .. get_sector_display() .. "Aminon Frags: " .. frag_1 .. frag_2 .. frag_3 .. frag_4 .. "| Seal: " .. seal

	else
		--sortie_display:hide()
    end
	
	local Gallionaire_logo = get_gallionaire_logo()
    local text = string.format(
        '%s | %s %s | %s | Gallimaufry: %s | Instance Record: %s | \\cs(%d,%d,%d)Instance Gallimaufry: %s\\cr%s',
        Gallionaire_logo, dot_color, ruspix_time_str,time_str, format_with_commas(previous_gallimaufry), format_with_commas(gallimaufry_record), color.red, color.green,
        color.blue, format_with_commas(earned_gallimaufry), shard_metal_display)
    -------------------------------------------------------------
    -- white
    display:color(255, 255, 255)

    -- Update display with formatted text
    display:text(text)

    display_message(earned_gallimaufry)
end

function update_sortie_display()
	    local lines = {}
    for i = 1, #sectors do
        table.insert(lines, string.format('Sector #%s', sectors[i].name))
        for j = 1, #sectors[i].npcs do
            local index = sectors[i].npcs[j]
            local location = 'Unknown'
            if npc_status[index] then
                if npc_status[index].map then
                    location = map_location[npc_status[index].map][npc_status[index].position] or 'Unknown'
                    location = string.format('\\cs(%s)%s\\cr', j == 1 and '255,95,101' or '193,100,255', location)
                end
                if npc_status[index].hidden then
                    location = 'Not Spawned'
                end
                if npc_status[index].dead then
                    location = '\\cs(51,240,65)Dead\\cr'
                end
            end
            table.insert(lines, string.format('    %s = %s', tracked_npc[index], location))
        end
    end

	---------------------------------------------------------------
	--if flags.in_sortie_zone == true then
		sortie_display:text(table.concat(lines, '\n'))
		sortie_display:show()
	--end
end

local function update_aminon_display()
    local lines = {}
    for name, data in pairs(absorb_counts) do
        local last_num = string.format("%4d", data.last) -- fixed width first
        local last_str
        if data.last > 300 then
            last_str = string.format("\\cs(255,0,0)%s\\cr",last_num)
        else
            last_str = last_num
        end

        -- Pad name to fixed width before printing
        local line = string.format("%-12s | Count:%3d | Last:%s | Total:%5d",
            name, data.count, last_str, data.total
        )
        table.insert(lines, line)
    end

    table.sort(lines)
    if #lines > 0 then
        aminon_display:text(table.concat(lines, '\n'))
    else
        aminon_display:text('')
    end
end

windower.register_event('action', function(act)
    if not flags.in_sortie_zone then return end -- stop this from firing unless we're in sortie
    if act.category == 4 or act.category == 3 then 
        local spell_id = act.param
        local doer = windower.ffxi.get_mob_by_id(act.actor_id)
		local shitheels = act.targets
		local maintarget = windower.ffxi.get_mob_by_id(shitheels[1].id)
		if doer and maintarget and maintarget.name == "Aminon" then
			if doer.name and spell_id == 275 then
				local absorbed = 0
				for _, target in ipairs(act.targets) do
					for _, action in ipairs(target.actions) do
						absorbed = absorbed + (action.param or 0)
					end
				end

				if not absorb_counts[doer.name] then
					absorb_counts[doer.name] = {count = 0, last = 0, total = 0}
				end

				local entry = absorb_counts[doer.name]
				entry.count = entry.count + 1
				entry.last  = absorbed
				entry.total = entry.total + absorbed
				if absorbed > 380 then
					windower.play_sound(sound_paths.warning)
				end
				aminon_display:show()
				update_aminon_display()
			end
		end
    end
end)

toggle_sound = true
toggle_sound = settings.toggle_sound

-- Function to toggle the sound
local function toggleSound()
    toggle_sound = not toggle_sound
    if toggle_sound then
        windower.add_to_chat(207, "Sound effects are now ON.")
    else
        windower.add_to_chat(207, "Sound effects are now OFF.")
    end
    settings.toggle_sound = toggle_sound
    config.save(settings)
end

windower.register_event('login', function()
    -- Check the player name or ID on login
    local player = windower.ffxi.get_player()
    if player and player.name ~= current_character then
	    coroutine.sleep(5)
	    induct_data()
		coroutine.sleep(3)
        print('Character switched from '..current_character..' to '..player.name)
        current_character = player.name
    end
end)
-- Commands
windower.register_event('addon command', function(...)
    local args = {...}
    args[1] = args[1]:lower()
    if args[2] then
        args[2] = args[2]:lower()
    end
    if args[1] == 'reset' then 
		earned_gallimaufry = 0
		aminon_display:hide()
        update_display()
    elseif args[1] == 'reload' or args[1] == 'r' then
        windower.send_command('lua r gallionaire')
    elseif args[1] == 'togglesound' or args[1] == 'ts' then
        toggleSound()
    elseif args[1] == 'show' then
        display:show()
    elseif args[1] == 'hide' then
        display:hide()
	elseif args[1] == 'pickup' then
        start_shinyplate_timer()
		coroutine.sleep(0.2)
		update_display()
        --------------------------------------------
	elseif args[1] == 'resettimer' then
		plates.shiny.start_time = plates.shiny.start_time - remaining_time + (remaining_time * .0001)  
		plates.shiny.timer = plates.shiny.start_time
		settings.plates.shiny.start_time = plates.shiny.start_time
		settings.plates.ruspix.start_time = os.time() 
		settings:save()
		plates.ruspix.start_time = settings.plates.ruspix.start_time
		update_display()
    elseif args[1] == 'setruspix' then
        plates.ruspix.manually_entered = tonumber(args[2])
		update_display()
        --------------------------------------------
    elseif args[1] == 'tp' then
		if aminon_display:visible() then
			aminon_display:hide()
		else
			aminon_display:show()
		end
    elseif args[1] == 'tpreset' then
        absorb_counts = {}
		aminon_display:hide()
		update_aminon_display()
        log('Absorb-TP readout reset.')
    elseif args[1] == 'auto' then
        if args[2] == 'on' then
            settings.Auto = true
        elseif args[2] == 'off' then
            settings.Auto = false
		else
			if settings.Auto == true then
				settings.Auto = false
			else
				settings.Auto = true
			end
        end
        update_doors()
        log('Automatic door opening %s.':format(settings.Auto and 'enabled' or 'disabled'))
        settings:save()
    elseif args[1] == 'help' then
        --windower.add_to_chat(207, 'Gallionaire help:')
        windower.add_to_chat(207, 'Commands: \n //ga reset \n //ga togglesound / ts \n //ga reload / r \n //ga hide \n //ga show \n //ga tp \n //ga tpreset \n //ga setruspix ')
        windower.add_to_chat(207, 'reset : sets the instance gallimaufry to 0.')
        windower.add_to_chat(207, 'togglesound / ts: toggle sound fx off & on (default On).')
        windower.add_to_chat(207, 'show makes the display visible (default).')
        windower.add_to_chat(207, 'hide: hides the display box')
		windower.add_to_chat(207, 'tp : Toggles visibility of the Aminon absorb-tp readout')
		windower.add_to_chat(207, 'tpreset : resets the Aminon absorb-tp readout')
		windower.add_to_chat(207, 'setruspix: manually update your ruspix plate timer (when you first enter sortie it will tell you the # of seconds, enter //ga setruspix thisnumber  to update the timer if needed.)')
        windower.add_to_chat(207, 'reload / r: reloads addon.')
        windower.add_to_chat(207, 'Enjoy!')
	else
		log('You went full retard... you never go full retard.')
		coroutine.sleep(2)
		windower.send_command('ga help')
    end
end)

-- Save the highest record when the addon is unloaded or the player zones out
function save_record()
    if earned_gallimaufry > 1 and earned_gallimaufry > gallimaufry_record and earned_gallimaufry < 100000 then
        gallimaufry_record = earned_gallimaufry
        settings.gallimaufry_record = gallimaufry_record
        settings:save()
		coroutine.sleep(0.2)
		update_display()
    end
    coroutine.sleep(1)
    if gallimaufry_record >= earned_gallimaufry then
        windower.send_command('ga reset')
		coroutine.sleep(0.2)
		update_display()
    end
    
end

local function check_zone()
	local zone_id = windower.ffxi.get_info().zone
    if zone_id == 275 or zone_id == 133 or zone_id == 189 then
        flags.in_sortie_zone = true
		flags.polling_zone = true
		flags.entered_sortie_now = true
        flags.in_leafalia = false
        flags.in_silverknife = false
        coroutine.schedule(function()
            induct_data()
			absorb_counts = {}
			zone_in_amount = previous_gallimaufry
            update_display()
        end, 2)
	elseif zone_id == 267 or zone_id == 281 or zone_id == 283 then
        flags.polling_zone = true
            if zone_id == 283 then
                flags.in_silverknife = true
            else
                flags.in_silverknife = false
            end
            if zone_id == 281 then
                flags.in_leafalia = true
            else
                flags.in_leafalia = false
            end
    else
        flags.in_silverknife = false
        flags.in_leafalia = false
        flags.in_sortie_zone = false
		flags.entered_sortie_now = false
    end
end

windower.register_event('unload', function() 
	save_record()
	save_ruspix_data()
end)

windower.register_event('load', function()
    windower.add_to_chat(207,'Welcome to Gallionaire 2.5! \n//ga help for a list of commands.')
    display:show()
	update_display()
	windower.play_sound(sound_paths.loading)
    coroutine.schedule(function()
		load_timer_from_settings()
		check_zone()
    end, 1)
    local player = windower.ffxi.get_player()
    if player then
        current_character = player.name
    end
    if tracked_zone[windower.ffxi.get_info().zone] then
        next_refresh = os.time() + initial_delay
    end
end)

windower.register_event('zone change', function(new_id, old_id)
    flags.zoning = true
	last_zone_time = os.time()
	oh_notifier = {}
    coroutine.schedule(function()
        flags.zoning = false
    end, 10)
    coroutine.schedule(function()
		if new_id == 275 or new_id == 133 or new_id == 189 then
			last_threshold = 0
			flags.polling_zone = true
			flags.in_sortie_zone = true
			flags.entered_sortie_now = true
            flags.in_leafalia = false
            flags.in_silverknife = false
			windower.send_command('ga reset')
			absorb_counts = {}
			induct_data()
			zone_in_amount = previous_gallimaufry
			update_display()
		elseif new_id == 267 or new_id == 281 or new_id == 283 then
			flags.polling_zone = true
            if new_id == 283 then
                flags.in_silverknife = true
            else
                flags.in_silverknife = false
            end
            if new_id == 281 then
                flags.in_leafalia = true
            else
                flags.in_leafalia = false
            end
		else
            flags.in_leafalia = false
            flags.in_silverknife = false
			flags.polling_zone = false
		end
		if old_id == 275 or old_id == 133 or old_id == 189 then
			flags.in_sortie_zone = false
			flags.entered_sortie_now = false
			zone_in_amount = nil
			log('Total haul: ' .. earned_gallimaufry)
			save_record()
		end
	end,6)
	-----------------------------------
    npc_status = {}
    if tracked_zone[new_id] then
        next_refresh = os.time() + initial_delay
    else
        next_refresh = nil
        sortie_display:text('')
        sortie_display:hide()
    end
	--------------------------------------
	last = {}
    doors:clear()
end)

windower.register_event('prerender', function()
    if not windower.ffxi.get_info().logged_in then
        frame_count = 0
        return
    end
	if flags.in_sortie_zone then
		frame_count = frame_count + 1
		if frame_count == 30 then
			update_doors()
			frame_count = 0
		end
		local open = T{}
		if settings.Auto then
			for index in doors:it() do
				local door = windower.ffxi.get_mob_by_index(index)
				if check_door(door) then
					open[door.index] = door.id
				end
			end
		else
			local door = windower.ffxi.get_mob_by_target()
			if door and check_door(door) then
				open[door.index] = door.id
			end
		end

		for id, index in open:it() do
			packets.inject(packets.new('outgoing', 0x01A, {
				['Target'] = id,
				['Target Index'] = index
			}))
			last[index] = os.time()
		end
	end
end)

windower.register_event('postrender', function() 
    if not next_refresh or next_refresh > os.time() then return end
    windower.add_to_chat(207, 'Gallionaire scanning NPCs ...')
    next_refresh = os.time() + refresh_interval
    for index, _ in pairs(tracked_npc) do
        npc_status[index] = npc_status[index] or {}
        npc_status[index].wait_ping = true
        windower.packets.inject_outgoing(0x016, string.pack('IHH', 0x0216, index, 0))
    end
end)

windower.register_event('time change', function()
    if flags.polling_zone then
		update_display()
   else
		local the_real = os.time() 
		if the_real % 3 == 0 then
			update_display()
		end
   end
end)