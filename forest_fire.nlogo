; --- Globals and Breeds ---

globals [
  initial-combustible-patches
  burned-patches
  fire-speed
  prev-burning
  total-fire-speed
  avg-fire-speed
  total-water-dropped
  total-drops-made
  extinguished-fires
  wet-patches-count
]

breed [aircraft plane]

patches-own [
  fuel-type
  is-burning?
  flammability
  burn-timer
  wet-timer
  slow-timer        ;; reduces spread speed for a few ticks
  cooldown-timer    ;; prevents ignition for a few ticks after drying
]

aircraft-own [
  water-load
  state
  my-target
  run-heading
]

; --- Setup Procedures ---

to setup
  clear-all
  setup-patches
  setup-fire
  setup-aircraft
  update-visuals
  reset-ticks
end

to setup-patches
  let world-area count patches
  let lake-area world-area * lake-density / 100
  let lake-radius sqrt (lake-area / pi)
  let lake-center one-of patches  ; Random patch as center of the lake

  ask patches [
    set is-burning? false
    set burn-timer 0
    set wet-timer 0

    ifelse distance lake-center <= lake-radius [
      set fuel-type "lake"
      set flammability 0
    ] [
      ifelse random-float 100 < grass-density [
        set fuel-type "grass"
        set flammability 80
      ] [
        set fuel-type "tree"
        set flammability 40
      ]
    ]
  ]

  set initial-combustible-patches count patches with [fuel-type = "tree" or fuel-type = "grass"]
  set burned-patches 0
end

to setup-fire
  ;; reset fire stats
  set total-fire-speed 0
  set avg-fire-speed 0
  set fire-speed 0
  set prev-burning 0

  if start-direction = "north" [
    ask patches with [pycor = max-pycor and (fuel-type = "tree" or fuel-type = "grass")] [
      ignite
    ]
  ]

  if start-direction = "south" [
    ask patches with [pycor = min-pycor and (fuel-type = "tree" or fuel-type = "grass")] [
      ignite
    ]
  ]

  if start-direction = "west" [
    ask patches with [pxcor = min-pxcor and (fuel-type = "tree" or fuel-type = "grass")] [
      ignite
    ]
  ]

  if start-direction = "east" [
    ask patches with [pxcor = max-pxcor and (fuel-type = "tree" or fuel-type = "grass")] [
      ignite
    ]
  ]
end

to setup-aircraft
  create-aircraft number-of-planes [
    set shape "airplane 2"
    set size 15
    setxy random-pxcor random-pycor
    set state "active"
    set water-load max-water-capacity
    set my-target nobody
    set run-heading heading
  ]
end


; --- Main Simulation Loop ---

to go
  if not any? patches with [is-burning?] and not any? patches with [wet-timer > 0] [
    stop
  ]
  ask aircraft [ move-and-act ]
  spread-fire
  update-burning-patches
  dry-out-patches
  dry-out-patches
  update-cooldowns

  update-visuals
  ask patches with [slow-timer > 0] [
    set slow-timer slow-timer - 1
  ]
  update-rate
  if ticks > 0 and fire-speed > 0 [
    update-fire-speed-rate
  ]
  tick
end


; --- Fire Behavior ---

to spread-fire
  ask patches with [is-burning?] [
    ask neighbors4 with [
      not is-burning? and
      wet-timer = 0 and
      cooldown-timer = 0 and
      (fuel-type = "tree" or fuel-type = "grass")
    ] [
      ;; base probability from slider
      let probability probability-of-spread
      if slow-timer > 0 [
        set probability probability * 0.1
      ]
      ;; direction from this neighbor patch (potential target) to the burning patch (myself)
      let direction towards myself

      ;; Adjust probability based on wind directions

      ;; Assuming wind directions and speeds as sliders:
      ;; south-wind-speed and west-wind-speed are sliders (values 0-100)

      if direction = 0 [
        ;; burning patch is north of neighbor
        ;; south wind impedes fire spreading from north to south neighbor
        set probability probability - south-wind-speed
      ]
      if direction = 90 [
        ;; burning patch is east of neighbor
        ;; west wind impedes spreading from east to west neighbor
        set probability probability - west-wind-speed
      ]
      if direction = 180 [
        ;; burning patch is south of neighbor
        ;; south wind aids fire spreading from south to north neighbor
        set probability probability + south-wind-speed
      ]
      if direction = 270 [
        ;; burning patch is west of neighbor
        ;; west wind aids spreading from west to east neighbor
        set probability probability + west-wind-speed
      ]

      set probability probability * (flammability / 100)

      if random 100 < probability [
        ignite
      ]
    ]
  ]
end

to ignite  ; Patch procedure
  set is-burning? true
  set burn-timer 0
  set burned-patches burned-patches + 1
end

; --- Firefighter Plane Behavior ---

to move-and-act  ; Aircraft procedure
  if state = "active" [
    hunt-fire
    if water-load <= 0 [
      set state "refilling"
    ]
  ]
  if state = "refilling" [
    seek-lake
  ]
end

to hunt-fire
  ;; If we don't have a target, or it's burned out, get a new one
  if my-target = nobody or not [is-burning?] of my-target [
    if any? patches with [is-burning?] [
      set my-target min-one-of patches with [is-burning?] [distance myself]
      set run-heading towards my-target
    ]
  ]

  ;; If we have a target, start/continue a bombing run
  if my-target != nobody [
    let turn-angle subtract-headings run-heading heading
    set heading heading + limit-turn turn-angle 8  ;; smooth turning

    ;; Edge avoidance before moving
    if patch-ahead 3 = nobody [
      rt 20
    ]
    avoid-collisions

    fd 2

    ;; Drop water if over burning patches
    if any? patches in-radius 5 with [is-burning?] [
      drop-water
    ]

    ;; If we've passed the target, clear it for a new run
    if distance my-target > 1[; and not [is-burning?] of my-target [
      set my-target nobody
    ]
  ]
end

to avoid-edge
  if patch-ahead 3 = nobody [
    rt 30
  ]
end

to-report limit-turn [angle max-turn]
  if angle > max-turn [
    report max-turn
  ]
  if angle < (- max-turn) [
    report (- max-turn)
  ]
  report angle
end

to seek-lake  ; Aircraft procedure
  let target-lake min-one-of patches with [fuel-type = "lake"] [distance myself]
  if target-lake != nobody [
    face target-lake
    avoid-collisions  ; Check for other planes before moving
    fd 1
    if patch-here = target-lake [ refill-water ]
  ]
end

to avoid-collisions  ; New procedure for aircraft
  ; If there are any other aircraft within a 3-patch radius...
  if any? other aircraft in-radius 3 [
    ; ...then turn a random amount (between -45 and 45 degrees) to find a clear path.
    rt (random 90) - 45
  ]
end

to drop-water
  let drop-length 5
  let max-radius 3

  let dist 0
  while [dist <= drop-length] [
    let center patch-at-heading-and-distance (heading + 180) dist
    if center != nobody [
      let radius (max-radius * dist) / drop-length
      ask center [
        ask patches in-radius radius with [fuel-type != "ash"] [
          douse
        ]
      ]
    ]
    set dist dist + 1
  ]

  ;; Track water usage
  let water-used 1
  set total-water-dropped total-water-dropped + water-used
  set water-load water-load - water-used
end

to douse
  ;; Extinguish if burning
  if is-burning? [
    set is-burning? false
    set extinguished-fires extinguished-fires + 1
  ]

  ;; Wet all flammable patches except ash
  if fuel-type != "ash" and fuel-type != "lake" [
    if wet-timer = 0 [
      set wet-patches-count wet-patches-count + 1
    ]
    set wet-timer time-to-dry
  ]
end


to refill-water  ; Aircraft procedure
  set water-load max-water-capacity
  set state "active"
end

; --- Environmental and State Changes ---

to update-rate
  let current-burning count patches with [pcolor = red]
  set fire-speed current-burning - prev-burning
  set prev-burning current-burning
end

to update-fire-speed-rate
  set total-fire-speed total-fire-speed + fire-speed
  set avg-fire-speed total-fire-speed / ticks
end

to update-burning-patches
  ask patches with [is-burning?] [
    set burn-timer burn-timer + 1
    if burn-timer > time-to-ash [
      become-ash
    ]
  ]
end

to become-ash
  set is-burning? false
  set fuel-type "ash"
end

to dry-out-patches
  ask patches with [wet-timer > 0] [
    set wet-timer wet-timer - 1
    if wet-timer = 0 [
      set cooldown-timer 30   ;; 30-ticks before it can catch fire again
    ]
  ]
end

to update-cooldowns
  ask patches with [cooldown-timer > 0] [
    set cooldown-timer cooldown-timer - 1
  ]
end

; --- Visualization ---

to update-visuals
  ask patches [
    if fuel-type = "lake" [
      set pcolor 104 ; dark-blue
    ]
    if fuel-type = "tree" [
      set pcolor green
    ]
    if fuel-type = "grass" [
      set pcolor lime
    ]
    if fuel-type = "ash" [
      set pcolor red - 3.5
    ]
    if is-burning? [
      set pcolor red
    ]
    if wet-timer > 0 and not is-burning? [
      set pcolor blue ; light-blue
    ]
  ]

  ask aircraft [
    ifelse state = "active"
      [ set color black ]
      [ set color gray + 2 ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
224
21
734
532
-1
-1
2.0
1
10
1
1
1
0
0
0
1
-125
125
-125
125
1
1
1
ticks
30.0

BUTTON
116
37
185
73
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
33
36
103
72
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
25
94
197
127
lake-density
lake-density
0
80
20.0
1
1
NIL
HORIZONTAL

SLIDER
24
139
196
172
grass-density
grass-density
0
100
30.0
1
1
NIL
HORIZONTAL

SLIDER
25
187
197
220
number-of-planes
number-of-planes
0
5
5.0
1
1
NIL
HORIZONTAL

SLIDER
24
237
196
270
time-to-ash
time-to-ash
5
50
25.0
1
1
NIL
HORIZONTAL

MONITOR
766
46
869
91
is-burning?
count patches with [is-burning?]
17
1
11

MONITOR
766
123
871
168
count aircraft
count aircraft
17
1
11

MONITOR
768
191
874
236
ticks
ticks
17
1
11

SLIDER
22
284
194
317
time-to-dry
time-to-dry
10
100
100.0
1
1
NIL
HORIZONTAL

SLIDER
439
575
641
608
probability-of-spread
probability-of-spread
0
50
15.0
1
1
%
HORIZONTAL

PLOT
888
42
1159
240
Fire Spread
ticks
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"Burning Patches" 1.0 0 -16777216 true "" "plot count patches with [is-burning?]"
"Total Ash" 1.0 0 -7500403 true "" "plot count patches with [fuel-type = \"ash\"]"

SLIDER
22
339
194
372
max-water-capacity
max-water-capacity
10
200
200.0
10
1
NIL
HORIZONTAL

TEXTBOX
376
5
606
59
FOREST FIRE WITH FIREFIGHTING PLANES
11
0.0
1

SLIDER
254
547
427
580
south-wind-speed
south-wind-speed
-25
25
0.0
1
1
NIL
HORIZONTAL

SLIDER
255
595
428
628
west-wind-speed
west-wind-speed
-25
25
0.0
1
1
NIL
HORIZONTAL

MONITOR
767
313
932
358
Average Fire Spread Speed
avg-fire-speed
2
1
11

MONITOR
767
255
961
300
Fire Spread Speed (patches/tick)
fire-speed
3
1
11

MONITOR
768
373
895
418
total-water-dropped
total-water-dropped
2
1
11

PLOT
1180
43
1417
242
Total Water Dropped
ticks
water dropped
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-water-dropped"
"pen-1" 1.0 0 -7500403 true "" "plot ticks"

CHOOSER
655
569
794
614
start-direction
start-direction
"north" "south" "east" "west"
3

MONITOR
769
434
871
479
burned-patches
burned-patches
17
1
11

@#$#@#$#@
## WHAT IS IT?



## HOW IT WORKS



## HOW TO USE IT


## THINGS TO NOTICE


## THINGS TO TRY

## EXTENDING THE MODEL

## NETLOGO FEATURES

## RELATED MODELS

## CREDITS AND REFERENCES

## HOW TO CITE

## COPYRIGHT AND LICENSE
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

airplane 2
true
0
Polygon -7500403 true true 150 26 135 30 120 60 120 90 18 105 15 135 120 150 120 165 135 210 135 225 150 285 165 225 165 210 180 165 180 150 285 135 282 105 180 90 180 60 165 30
Line -7500403 false 120 30 180 30
Polygon -7500403 true true 105 255 120 240 180 240 195 255 180 270 120 270

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
set density 60.0
setup
repeat 180 [ go ]
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
