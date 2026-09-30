# Micro_Bot

A Roblox swarm of tiny black microbots, inspired by *Big Hero 6*. The bots lie scattered on the ground and crawl around. Press **E** and they link together into a form that follows your mouse:

- **Snake**: a long twisting body. Its raised head chases your cursor and the body slithers behind it.
- **Spider army**: one spider for every 200 bots. Every spider has 8 legs that step on their own, and spiders climb walls, ladders, stairs and ceilings.
- **Megabot**: big microbots built out of microbots, with spike limbs and a red angry face. One megabot for every 400 bots.

You can run 1 to 20,000 bots. Everything runs on the client in one LocalScript.

## Controls

| Input | Action |
|---|---|
| **E** (or the SCATTERED / LINKED button) | Link the bots into the current form, or scatter them |
| **Q** (or the SNAKE / SPIDER / MEGABOT buttons) | Switch form. While linked, the bots flow straight into the new shape |
| **Mouse** | Steer. The swarm heads for whatever you point at |
| **Slider / number box** (bottom-left panel) | Swarm size, 1 to 20,000 |

For spiders, point at a wall to climb it, then at the ceiling to crawl on it upside down. Point at the floor below them to make them drop. Climb ladders from the front.

## Setup

### Option A: Rojo

This repo is a [Rojo](https://rojo.space) project. `default.project.json` maps the script to `StarterPlayer.StarterPlayerScripts.MicrobotController`.

```
rojo serve
```

Then connect from the Rojo plugin in Studio.

### Option B: copy and paste

In Studio, create a **LocalScript** named `MicrobotController` in `StarterPlayer > StarterPlayerScripts`. Paste in the contents of `src/client/MicrobotController.client.luau`.

### The bot model

The script uses `ReplicatedStorage.Microbot` as the look of a single bot. To create it, paste `tools/BuildMicrobotModel.luau` into Studio's **Command Bar** (View → Command Bar) and press Enter. It can be a single part or a Model, so you can restyle it freely. If it's missing, the script waits 10 seconds and then falls back to small black balls.

`tools/BuildSpiderTestCourse.luau` builds an optional obstacle course with a wall, a ceiling, a ladder and stairs for trying out the spiders. Run it the same way.

## Settings

All settings are at the top of `MicrobotController`.

| Setting | Default | What it does |
|---|---|---|
| `MAX_BOTS` / `START_BOTS` | 20000 / 1000 | Swarm size limit and starting count |
| `BOT_SCALE` | 0.5 | Size of one bot (1 ≈ 0.5 studs long). Smaller bots make smaller forms |
| `START_FORM` | `"snake"` | Form used the first time you press E |
| `SPIDER_BOTS_EACH` | 200 | Bots per spider. Lower means more, smaller spiders |
| `SPIDER_SPEED` | 10 | Spider walk speed (4–6 looks more natural for tiny spiders) |
| `MEGA_BOTS_EACH` | 400 | Bots per megabot |
| `HEAD_HEIGHT`, `SLITHER_AMP`, `TWIST_SPEED` | 3, 0.7, 1.6 | Snake look |
| `TOGGLE_KEY` / `FORM_KEY` | E / Q | Key bindings |

## Performance

Every bot is a real part, so the cost grows with the bot count. To save work, bots that have settled into a spider are welded to invisible joints, so a standing spider army costs almost nothing. These frame rates were measured in Studio on a desktop PC, with the spider army:

| Bots | Spiders | Standing | Walking |
|---|---|---|---|
| 4,000 | 20 | 144 fps | 80 fps |
| 10,000 | 50 | 139 fps | 37 fps |
| 20,000 | 100 | 72 fps | 19 fps |

For phones and weaker PCs, about 4,000–6,000 bots is a good range. The swarm exists only on the local player's screen, so other players don't see it.

## Files

```
default.project.json                      Rojo project
src/client/MicrobotController.client.luau the whole swarm (LocalScript)
tools/BuildMicrobotModel.luau             Command Bar script: builds ReplicatedStorage.Microbot
tools/BuildSpiderTestCourse.luau          Command Bar script: builds the spider test course
```
