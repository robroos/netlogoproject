extensions [ csv ]

globals [
          electricity-price
          oil-price
          co2-storage-price
          co2-emission-price
          current-capture-technology-price
          current-capture-technology-capacity
          capture-efficiency
          total-co2-emitted
          total-co2-stored
          total-co2-storage-industry-costs
          co2-stored-current-year
          subsidy-per-industry-without-ccs
          dispatched-subsidy-infrastructure
          dispatched-subsidy-industry
          oil-used
          electricity-used
          capture-electricity-usage
          ton-co2-emission-per-ton-oil
          connection-price
          last-pipeline
        ]

breed [ports-of-rotterdam port-of-rotterdam]
breed [industries industry]
breed [storage-points storage-point]
undirected-link-breed [pipelines pipeline]

ports-of-rotterdam-own [
                         money
                         co2-storage-income
                         subsidy-income
                         pipeline-expenditure
                       ]

industries-own [
                 payback-period
                 capture-technology-capacity
                 electricity-consumption
                 oil-consumption
                 co2-production
                 CCS-joined
                 pipe-joined
                 co2-storage
                 co2-emission
                 leftover
               ]

storage-points-own [
                     name
                     pipe-capacity
                     connected
                     onshore-distance
                     offshore-distance
                     onshore-capex
                     offshore-capex
                   ]

pipelines-own [
                extensible
                used-capacity
                max-capacity
                joined-industries
              ]

to setup
  clear-all
  file-close-all

  ask patches [set pcolor 96]
  ask patches with [pxcor <= max-pxcor and pxcor >= -2]
    [ set pcolor 68 ]

  set ton-co2-emission-per-ton-oil 3.2
  set connection-price 1
  set electricity-price 0.000075
  file-open "co2-oil-price.csv"
  let x csv:from-row file-read-line
  set co2-emission-price item 1 x
  set oil-price item 2 x
  set co2-storage-price 0.3
  set capture-electricity-usage 0.4
  set total-co2-emitted 0
  set co2-stored-current-year 0
  set yearly-government-subsidy 100
  set fraction-subsidy-to-pora 0.7
  set capture-efficiency 0.8
  set current-capture-technology-price 200
  set current-capture-technology-capacity 5

  set-default-shape ports-of-rotterdam "building institution"
  create-ports-of-rotterdam 1
  [
    set color white
    set size 2
    setxy -2 0
    set money 1000
    set co2-storage-income 0
    set subsidy-income 0
    set pipeline-expenditure 0
  ]

  set-default-shape industries "factory"
  ask n-of 25 patches with [ (pxcor > -1 and pxcor < 5) and (pycor > -7 and pycor < 7) ]
    [ sprout-industries 1 [
                            set color red
                            set size 1
                            set payback-period (1 + random 20)
                            set oil-consumption random 10 + 1
                            set co2-production oil-consumption * ton-co2-emission-per-ton-oil
                            set electricity-consumption 0
                            set CCS-joined false
                            set pipe-joined false
                            set co2-storage 0
                            set co2-emission co2-production
                            set leftover 0
                          ]
    ]

  set-default-shape storage-points "container"

  reset-ticks
end

to go
  update-prices
  update-KPI
  install-CCS
  pay-out-subsidy
  join-CCS
  build-pipelines
  allocate-storagepoints
  tick
end

to allocate-storagepoints
  if count storage-points = 0 or all? pipelines with [ extensible = true ] [ used-capacity = max-capacity ] or last-pipeline = "fixed"
    [
      file-open "storagepoints.csv"
      ifelse file-at-end? = false
        [ let x csv:from-row file-read-line
          create-storage-points 1 [
                                    setxy random-xcor random-ycor
                                    set name item 0 x
                                    set pipe-capacity item 3 x
                                    set onshore-distance item 1 x
                                    set offshore-distance item 2 x
                                    set onshore-capex item 4 x
                                    set offshore-capex item 5 x
                                    set connected false
                                  ]
        ]
        [ ]
    ]
end


to pay-out-subsidy
  ask port-of-rotterdam 0
  [
    set money money + yearly-government-subsidy * fraction-subsidy-to-pora
    set dispatched-subsidy-infrastructure dispatched-subsidy-infrastructure + yearly-government-subsidy * fraction-subsidy-to-pora
    set subsidy-income subsidy-income + yearly-government-subsidy * fraction-subsidy-to-pora]
    ifelse count industries with [CCS-joined = true] = count industries
      [set subsidy-per-industry-without-ccs 0]
      [set subsidy-per-industry-without-ccs yearly-government-subsidy * (1 - fraction-subsidy-to-pora) / count industries ;with [CCS-joined = false] nog even kijken naar subsidieverdeling > kan deze ook gebruikt worden om co2-storage van te betalen?
  ]
end

to build-pipelines
  ask port-of-rotterdam 0
    [
      if any? storage-points with [ connected = false ]
        [
          let sp one-of storage-points with [ connected = false ]
          ifelse [ pipe-capacity ] of sp - sum [ min list co2-production current-capture-technology-capacity ] of industries with [ CCS-joined = true ] <= 0.1 * [ pipe-capacity ] of sp
            [
              let pipe-capex [ onshore-distance * onshore-capex * 0.7 + offshore-distance * offshore-capex * 0.7 ] of sp
              if money >= pipe-capex
                [
                  create-pipeline-with sp
                    [
                      set used-capacity 0
                      set max-capacity [ pipe-capacity ] of sp
                      set extensible false
                    ]
                  set money money - pipe-capex
                  ask sp [ set connected true ]
                ]
            ]
            [
              let pipe-capex [ onshore-distance * onshore-capex + offshore-distance * offshore-capex ] of sp
              if money >= pipe-capex
                [
                  create-pipeline-with sp
                    [
                      set used-capacity 0
                      set max-capacity [ pipe-capacity ] of sp
                      set extensible true
                    ]
                  set money money - pipe-capex
                  ask sp [ set connected true ]
                ]
            ]
        ]
    ]
end

to update-prices
      set current-capture-technology-price current-capture-technology-price * 0.9
      set current-capture-technology-capacity current-capture-technology-capacity * 1.1
      set electricity-price electricity-price * 0.95
      set co2-storage-price co2-storage-price * 0.95

      if file-at-end? [ stop ]
      file-open "co2-oil-price.csv"
      let x csv:from-row file-read-line
      set co2-emission-price item 1 x
      set oil-price item 2 x
end

to join-CCS ;; the electricity (and oil?) consumption raises when CCS is used as a result of ineffeciency
  if any? pipelines with [ (extensible = false and used-capacity = 0) or (extensible = true and used-capacity < max-capacity) ]
       [
         ask industries with [ CCS-joined = false ]
           [
             let OPEX-without-CCS oil-price * oil-consumption + co2-production * co2-emission-price

             let co2-to-be-captured min list current-capture-technology-capacity (co2-production * capture-efficiency)
             let co2-to-be-emitted max list (co2-production * (1 - capture-efficiency)) co2-production - current-capture-technology-capacity
             let energy-costs-with-CCS electricity-price * capture-electricity-usage * min list current-capture-technology-capacity co2-production  + oil-price * oil-consumption

             let OPEX-with-CCS energy-costs-with-CCS + co2-to-be-captured * co2-storage-price + co2-to-be-emitted * co2-emission-price
             let CAPEX-CCS-with-subsidy current-capture-technology-price - subsidy-per-industry-without-ccs + connection-price
             ;set OPEX-with-CCS electricity-price * electricity-consumption * (1 + increase-energy-use-capture) + oil-price * oil-consumption + (min list current-capture-technology-capacity (co2-production * capture-efficiency)) * co2-storage-price + (max list (co2-production * (1 - capture-efficiency)) co2-production - current-capture-technology-capacity) * co2-emission-price + connection-price
             if CAPEX-CCS-with-subsidy + payback-period * OPEX-with-CCS < OPEX-without-CCS * payback-period
              [
                set CCS-joined true
                set color orange
                set total-co2-storage-industry-costs total-co2-storage-industry-costs + current-capture-technology-price ;update industry co2 costs with CAPEX
                set dispatched-subsidy-industry dispatched-subsidy-industry + subsidy-per-industry-without-ccs
              ]
           ]
       ]
end

to install-CCS
  ask industries [ if CCS-joined = true and capture-technology-capacity = 0
                     [
                       set capture-technology-capacity current-capture-technology-capacity
                       set color green
                       create-pipeline-with port-of-rotterdam 0 [ set color 3 ]
                       ask port-of-rotterdam 0 [ set money money + connection-price ]
                     ]
                 ]
end

to join-pipe-and-store-emit
  ask industries with [ CCS-joined = true and capture-technology-capacity != 0 and pipe-joined = false ]
   [
    ifelse any? pipelines with [ (extensible = true and used-capacity < max-capacity) or (extensible = false and used-capacity = 0) ]
      [
        set pipe-joined true
        set co2-emission max list (co2-production * (1 - capture-efficiency)) co2-production - capture-technology-capacity
        set co2-storage min list capture-technology-capacity (co2-production * capture-efficiency)
        set electricity-consumption min list capture-technology-capacity co2-production * capture-electricity-usage
        ask one-of pipelines with [ (extensible = true and used-capacity < max-capacity) or (extensible = false and used-capacity = 0) ]
          [
            ifelse [ co2-storage ] of myself <=  max-capacity - used-capacity
              [
                set used-capacity used-capacity + [ co2-storage ] of myself
                set joined-industries lput [ who ] of myself joined-industries
              ]
              [
                let rest max-capacity - used-capacity
                ask myself [
                             set leftover co2-storage - rest
                             set co2-emission leftover
                             set co2-storage co2-storage - leftover
                           ]
                set used-capacity max-capacity
                set joined-industries lput [ who ] of myself joined-industries
              ]
          ]

      ]
      [
        set co2-emission co2-production
        set co2-storage 0
        set co2-stored-current-year 0
      ]
   ]
  ask industries with [ leftover > 0 ]
    [
      if any? pipelines with [ extensible = true and used-capacity < max-capacity ] or any?  pipelines with [ extensible = false and used-capacity = 0 ]
        [
          ask one-of pipelines with [ (extensible = true and used-capacity < max-capacity) or (extensible = false and used-capacity = 0) ]
            [ set used-capacity used-capacity + [ leftover ] of myself ]
          set co2-emission co2-emission - leftover
          set co2-storage co2-storage + leftover
          set leftover 0
        ]
    ]
  ask pipelines [ if used-capacity = max-capacity [ set color red ] ]
end

to update-KPI
  set total-co2-stored total-co2-stored + sum [ used-capacity ] of pipelines
  set total-co2-emitted total-co2-emitted + sum [ co2-emission ] of industries
  set total-co2-storage-industry-costs total-co2-storage-industry-costs + co2-storage-price * co2-stored-current-year
  set oil-used oil-used + sum [ oil-consumption ] of industries
  set electricity-used electricity-used + sum [ electricity-consumption ] of industries
end
@#$#@#$#@
GRAPHICS-WINDOW
225
10
622
408
-1
-1
9.5
1
10
1
1
1
0
0
0
1
-20
20
-20
20
1
1
1
ticks
30.0

BUTTON
10
10
65
62
Setup
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

BUTTON
72
10
128
62
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
738
10
1108
223
Emission and Storage of CO2
Years
Tons
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"CO2-stored" 1.0 0 -13791810 true "" "plot total-co2-stored"
"CO2-emitted" 1.0 0 -2674135 true "" "plot total-co2-emitted"

SLIDER
8
68
205
101
yearly-government-subsidy
yearly-government-subsidy
0
1000
100.0
1
1
NIL
HORIZONTAL

SLIDER
8
105
206
138
fraction-subsidy-to-pora
fraction-subsidy-to-pora
0
1
0.7
0.1
1
NIL
HORIZONTAL

PLOT
741
231
1107
426
Costs to industry to store CO2
Year
Costs
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-co2-storage-industry-costs"

PLOT
1312
234
1512
428
Subsidy to Infrastructure
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot dispatched-subsidy-infrastructure"

PLOT
1110
233
1310
427
Subsidy to Industries
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot dispatched-subsidy-industry"

PLOT
1110
430
1518
606
Finance of Port of Rotterdam
Years
Euros
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Money" 1.0 0 -16777216 true "" "plot [money] of port-of-rotterdam 0"
"Storage income" 1.0 0 -7500403 true "" "plot [co2-storage-income] of port-of-rotterdam 0"
"Subsidy income" 1.0 0 -13840069 true "" "plot [subsidy-income] of port-of-rotterdam 0"
"Infrastructure expenditure" 1.0 0 -2674135 true "" "plot [pipeline-expenditure] of port-of-rotterdam 0"

PLOT
1109
10
1514
224
Total amount of energy used
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Oil use" 1.0 0 -16777216 true "" "plot oil-used"
"Electricity use" 1.0 0 -7500403 true "" "plot electricity-used"

PLOT
743
429
1107
607
Dispatched Subsidy by Government
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Infrastructure" 1.0 0 -16777216 true "" "plot dispatched-subsidy-infrastructure"
"Industry" 1.0 0 -7500403 true "" "plot dispatched-subsidy-industry"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

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

building institution
false
0
Rectangle -7500403 true true 0 60 300 270
Rectangle -16777216 true false 130 196 168 256
Rectangle -16777216 false false 0 255 300 270
Polygon -7500403 true true 0 60 150 15 300 60
Polygon -16777216 false false 0 60 150 15 300 60
Circle -1 true false 135 26 30
Circle -16777216 false false 135 25 30
Rectangle -16777216 false false 0 60 300 75
Rectangle -16777216 false false 218 75 255 90
Rectangle -16777216 false false 218 240 255 255
Rectangle -16777216 false false 224 90 249 240
Rectangle -16777216 false false 45 75 82 90
Rectangle -16777216 false false 45 240 82 255
Rectangle -16777216 false false 51 90 76 240
Rectangle -16777216 false false 90 240 127 255
Rectangle -16777216 false false 90 75 127 90
Rectangle -16777216 false false 96 90 121 240
Rectangle -16777216 false false 179 90 204 240
Rectangle -16777216 false false 173 75 210 90
Rectangle -16777216 false false 173 240 210 255
Rectangle -16777216 false false 269 90 294 240
Rectangle -16777216 false false 263 75 300 90
Rectangle -16777216 false false 263 240 300 255
Rectangle -16777216 false false 0 240 37 255
Rectangle -16777216 false false 6 90 31 240
Rectangle -16777216 false false 0 75 37 90
Line -16777216 false 112 260 184 260
Line -16777216 false 105 265 196 265

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

chess rook
false
0
Rectangle -7500403 true true 90 255 210 300
Line -16777216 false 75 255 225 255
Rectangle -16777216 false false 90 255 210 300
Polygon -7500403 true true 90 255 105 105 195 105 210 255
Polygon -16777216 false false 90 255 105 105 195 105 210 255
Rectangle -7500403 true true 75 90 120 60
Rectangle -7500403 true true 75 84 225 105
Rectangle -7500403 true true 135 90 165 60
Rectangle -7500403 true true 180 90 225 60
Polygon -16777216 false false 90 105 75 105 75 60 120 60 120 84 135 84 135 60 165 60 165 84 179 84 180 60 225 60 225 105

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

container
false
0
Rectangle -7500403 false false 0 75 300 225
Rectangle -7500403 true true 0 75 300 225
Line -16777216 false 0 210 300 210
Line -16777216 false 0 90 300 90
Line -16777216 false 150 90 150 210
Line -16777216 false 120 90 120 210
Line -16777216 false 90 90 90 210
Line -16777216 false 240 90 240 210
Line -16777216 false 270 90 270 210
Line -16777216 false 30 90 30 210
Line -16777216 false 60 90 60 210
Line -16777216 false 210 90 210 210
Line -16777216 false 180 90 180 210

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

factory
false
0
Rectangle -7500403 true true 76 194 285 270
Rectangle -7500403 true true 36 95 59 231
Rectangle -16777216 true false 90 210 270 240
Line -7500403 true 90 195 90 255
Line -7500403 true 120 195 120 255
Line -7500403 true 150 195 150 240
Line -7500403 true 180 195 180 255
Line -7500403 true 210 210 210 240
Line -7500403 true 240 210 240 240
Line -7500403 true 90 225 270 225
Circle -1 true false 37 73 32
Circle -1 true false 55 38 54
Circle -1 true false 96 21 42
Circle -1 true false 105 40 32
Circle -1 true false 129 19 42
Rectangle -7500403 true true 14 228 78 270

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

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

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

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.4
@#$#@#$#@
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
