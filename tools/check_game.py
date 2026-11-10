#!/usr/bin/env python3
"""Run Python and Godot checks; require success markers (Godot can exit 0 on parse errors)."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, marker=None):
    (ROOT / 'build').mkdir(exist_ok=True)
    # Fresh per-check profiles prevent front-end/reward tests from reading or
    # autosaving the player's Homeworld, even if they have earned voyage rewards.
    with tempfile.TemporaryDirectory(prefix='dominus-check-', dir=ROOT / 'build') as save_directory:
        environment = dict(os.environ, DOMINUS_SAVE_DIRECTORY=save_directory)
        if '--headless' in command:
            command = [command[0], '--log-file', str(Path(save_directory) / 'godot.log'), *command[1:]]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, env=environment)
    output = result.stdout + result.stderr
    if result.returncode or any(error in output for error in ["SCRIPT ERROR:", "ERROR: No loader found", "ERROR: Failed to load"]) or (marker and marker not in output):
        print(output)
        raise SystemExit(result.returncode or 1)
    print(marker or "Passed: " + " ".join(map(str, command[1:])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"])
    run([sys.executable, "tools/check_architecture.py"], "Architecture check: 0 violations")
    run([args.godot, "--headless", "--path", "game", "--editor", "--import"])
    for script, marker in [
        ("test_simulation", "Simulation and SQLite integration: 0 failures"),
        ("test_threaded_session", "Threaded fixed-tick ownership: 0 failures"),
        ("test_layer_drags", "Terrain layer geometry: 0 failures"),
        ("test_gameplay", "Gameplay and layer-drag integration: 0 failures"),
        ("test_front_end", "Front-end integration: 0 failures"),
        ("test_game_menu", "Game menu and live configuration controls: 0 failures"),
        ("test_campaign_hud", "Original campaign HUD: 0 failures"),
        ("test_hud_metrics", "Source HUD metrics and tribe state: 0 failures"),
        ("test_current_cards", "Complete original 2.4 cards and bounded image residency: 0 failures"),
        ("test_campaign_maps", "Original large campaign maps: 0 failures"),
        ("test_adventures", "Original voyages and deterministic island self-play: 0 failures"),
        ("test_voyage_scripts", "615 variants, 0 failures"),
        ("test_voyage_rewards", "Original voyage rewards, Homeworld spending and durable deduplication: 0 failures"),
        ("test_voyage_challenges", "Source voyage powers, champion protection, purification and shrine triggers: 0 failures"),
        ("test_adventures_menu", "Adventures menu, boat visit and Homeworld return: 0 failures"),
        ("test_progression", "Original chest, card and power rules: 0 failures"),
        ("test_playable_resources", "Playable chest resources, named cards and sparse source rocks: 0 failures"),
        ("test_resource_types_and_supply", "Typed resource matching, replenishing chests and occupied house belief: 0 failures"),
        ("test_typed_card_ui", "Original type icons and secondary-type card drops: 0 failures"),
        ("test_belief_collection", "Single-click belief, source-gated drag collection and gesture release: 0 failures"),
        ("test_shrine_priority", "Shrine repair priority, full footprints, clearance and saved jobs: 0 failures"),
        ("test_shrine_blockers", "Shrine blockers, covering-object selection and original clearing power: 0 failures"),
        ("test_campaign_economy", "Original research, settlements and harvest transport: 0 failures"),
        ("test_production_advances", "Source production advances and field ranks: 0 failures"),
        ("test_construction_work", "Original cooperative construction: 12 native cases, 0 failures"),
        ("test_tree_plots", "Original tree clearing and building plots: 0 failures"),
        ("test_source_scenery", "Original native initial scenery and immutable placement data: 0 failures"),
        ("test_source_plots", "Original native plot masks: 12288 samples, 0 failures"),
        ("test_source_plot_allocation", "Original new plot allocation: 9 cases, 704 biome samples, 0 failures"),
        ("test_existing_plots", "Original existing plot validation: 456 cases, 0 failures"),
        ("test_plot_resize", "Original plot resize: 64 native layout cases, 0 failures"),
        ("test_plot_registry", "Original plot registry: 18 region cases, 0 failures"),
        ("test_plot_schedule", "Original plot schedule: 49 neighborhoods, 8 dispatch cases, 0 failures"),
        ("test_source_influence", "Original influence raster: 17 circles, 49 gates, 191000 bytes, 0 failures"),
        ("test_influence_areas", "Original influence areas: 12 cases, 135360 bytes, 0 failures"),
        ("test_campaign_plots", "Original campaign plot integration: 0 failures"),
        ("test_build_candidates", "Original builder plot selection: 59 native cases, 0 failures"),
        ("test_plot_conversion", "Original plot conversion: 20 native cases, 0 failures"),
        ("test_build_start", "Original follower construction start: 15 native cases, 0 failures"),
        ("test_house_constructor", "Original house core initialization: 83 native cases, 0 failures"),
        ("test_house_factory", "Original house factory: 15 native cases, 0 failures"),
        ("test_target_references", "Original target references: 33 cases, 44 transitions, 0 failures"),
        ("test_construction_start", "Original integrated construction start: 25 native cases, 0 failures"),
        ("test_plot_cost", "Original plot cost: 100 native cases, 0 failures"),
        ("test_action_sequence", "Original action sequence: 438 native cases, 0 failures"),
        ("test_action_entry", "Original action entry: 459 native cases, 0 failures"),
        ("test_action_controller", "Original action controller: 133 native cases, 0 failures"),
        ("test_storm_chests", "Original storm chests: 53 refill cases, 10 disk cases, 15 batches, 0 failures"),
        ("test_chest_placement", "Original chest placement: 213 native cases, 0 failures"),
        ("test_chest_factory", "Original chest factory: 43 native cases, 0 failures"),
        ("test_chest_constructor", "Original chest constructor: 106 core cases, 7 factory cases, 0 failures"),
        ("test_chest_lifetime", "Original chest lifetime: 44 cases, 68 transitions, save continuation, 0 failures"),
        ("test_source_availability", "Original reward availability: 67 cases, 268 queries, save continuation, 0 failures"),
        ("test_chest_reward_capacity", "Original chest reward capacity: 7 cases, 21 transitions, save continuation, 0 failures"),
        ("test_weighted_rewards", "Original weighted rewards: 320 draws, 11 era values, 0 failures"),
        ("test_sticker_selection", "Original sticker selection: 544 cases, save restoration, 0 failures"),
        ("test_temple_sites", "Original temple sites, repair costs, completion gates and save continuation: 0 failures"),
        ("test_source_temple_repair", "Original temple repair: 236 cases, save restoration, 0 failures"),
        ("test_temple_terrain", "Original temple terrain: 312 cases, 32 sequence steps, save continuation, 0 failures"),
        ("test_temple_footprint", "Original temple footprint: 162 scans, 56 composed cases, 96 sequence steps, save continuation, 0 failures"),
        ("test_temple_frame", "Original temple pre-work frame: 276 native cases, 96 sequence steps, saved continuation, 0 failures"),
        ("test_temple_frame_repair", "Original temple frame and repair: 99 native cases, 48 sequence steps, saved continuation, 0 failures"),
        ("test_temple_membership", "Original temple membership: 191 geometry cases, 101 affiliation cases, 64 sequence steps, saved continuation, 0 failures"),
        ("test_temple_work", "Original temple work in playable repair, CSV reload and save continuation: 0 failures"),
        ("test_reward_dispatch", "Original reward dispatch: 266 cases, 74 deferred temple cases, save restoration, 0 failures"),
        ("test_reward_queue", "Original reward queue: 327 cases, 1147 transitions, save continuation, 0 failures"),
        ("test_source_card_research", "Original card research: 624 cases, 4920 transitions, save continuation, 0 failures"),
        ("test_researched_rewards", "Original researched rewards: 108 cases, 351 transitions, save continuation, 0 failures"),
        ("test_selected_rewards", "Original selected rewards: 432 cases, 2451 transitions, save continuation, 0 failures"),
        ("test_reward_catalog", "Original reward catalog: 71 cases, 142 bindings, save continuation, 0 failures"),
        ("test_registered_rewards", "Original registered rewards: 70 cases, 904 transitions, save continuation, 0 failures"),
        ("test_source_era", "Original era cache: 259 cases, 1035 queries, save continuation, 0 failures"),
        ("test_era_rewards", "Original era rewards: 15 cases, 98 transitions, save continuation, 0 failures"),
        ("test_unlock_dispatch", "Original unlock dispatch: 155 cases, 931 transitions, save continuation, 0 failures"),
        ("test_unlocked_rewards", "Original unlocked rewards: 79 cases, 638 transitions, save continuation, 0 failures"),
        ("test_unlock_lifetime", "Original unlock lifetime: 89 cases, 403 transitions, save continuation, 0 failures"),
        ("test_lifetime_rewards", "Original lifetime rewards: 6 cases, 116 transitions, save continuation, 0 failures"),
        ("test_temple_rewards", "Original temple rewards: 59 cases, 242 transitions, save continuation, 0 failures"),
        ("test_house_selection", "Original building selection: 4608 native cases, 0 failures"),
        ("test_source_terrain", "Original terrain sampling: 30976 corner cases, 192 source samples, 0 failures"),
        ("test_rock_motion", "Original rock motion: 8 native cases, 0 failures"),
        ("test_tree_response", "Original tree response: 7 terrain cases, 162 scale cases, 0 failures"),
        ("test_campaign_opening", "Authored Homeworld6 rescue and source callbacks: 0 failures"),
        ("test_campaign_camera", "Authored trail camera observation and guarded catch-up: 0 failures"),
        ("test_campaign_trail", "Authored full trail, terrain gestures and trailing-follower arrival: 0 failures"),
        ("test_promised_land", "Source Promised Land arrival, rock exception and midnight callbacks: 0 failures"),
        ("test_campaign_opening_ui", "Source opening prompts and original animation roles: 0 failures"),
        ("test_economy_interface", "Research gallery and settlement controls: 0 failures"),
        ("test_building_info", "Original building selection, live statistics and detached queries: 0 failures"),
        ("test_card_completion_ui", "Resource card completion, upgrades and playable power unlocks: 0 failures"),
        ("test_resource_assignment", "Original resource dragging, partial assignments and card completion: 0 failures"),
        ("test_three_unit_tables", "Three OpenOffice unit tables: 0 failures"),
        ("test_render_batches", "Source building and scenery batches: 0 failures"),
        ("test_live_configuration", "Settings, live balance and continued growth: 0 failures"),
        ("test_coastal_rocks", "Bare coast and anchored rocks: 0 failures"),
        ("test_influence", "God influence and expansion: 0 failures"),
        ("test_navigation", "Trackpad navigation and streamed terrain: 0 failures"),
        ("test_campaign_growth", "Original Homeworld extended self-play: 0 failures"),
        ("test_campaign", "Original Homeworld campaign self-play: 0 failures"),
        ("test_original_assets", "Original characters and audio: 0 failures"),
        ("test_example_world", "models, 0 failures"),
        ("test_exhibit_playback", "Exhibit habitats and playback: 371 clips, 0 failures"),
    ]:
        run([args.godot, "--headless", "--path", "game", "--script", f"res://tests/{script}.gd"], marker)


if __name__ == "__main__":
    main()
