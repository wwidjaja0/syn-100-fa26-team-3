"""The procedural low-poly props: one function per prop, each returning a Model (model.py).

python3 generate_assets.py            rewrites every assets/<NN_name>.glb and asset_manifest.json

Needs the pinned versions in requirements.txt (trimesh 4.5.3). The GLBs feed
pipeline/scene/build_pixel_scene.py, which places them in the room. Conventions (sizes, naming,
glowing parts, colours) are in ASSET_GUIDE.md; how to add a prop is in docs/HOW_TO.md.
"""
import json, math
import numpy as np
import trimesh
from model import Model, PAL, ROOT, OUT

def workbench():
 m=Model('Wooden workbench')
 # 2.05 wide, .77 deep; 0.92 tall
 for x in [-.89,.89]:
  for y in [-.28,.28]:
   m.box('squared_oak_leg',(x,y,.42),(.115,.115,.84),'walnut')
   m.box('steel_foot_plate',(x,y,.035),(.14,.14,.07),'steel_dark')
 m.box('rear_stretcher',(0,.29,.30),(1.83,.07,.10),'walnut')
 m.box('front_stretcher',(0,-.29,.30),(1.83,.07,.1),'walnut')
 m.box('end_stretcher_left',(-.89,0,.29),(.07,.62,.09),'walnut')
 m.box('end_stretcher_right',(.89,0,.29),(.07,.62,.09),'walnut')
 m.box('lower_shelf',(0,.0,.34),(1.75,.57,.045),'wood_dark')
 for i in range(5):
  m.box('tabletop_plank',(0,-.34+i*.17,.90),(2.06,.166,.11),'wood_light' if i%2 else 'oak')
 m.box('tabletop_front_nosing',(0,-.425,.9),(2.11,.06,.13),'walnut_light')
 m.box('top_side_nosing_left',(-1.025,0,.9),(.065,.83,.13),'wood_dark')
 m.box('top_side_nosing_right',(1.025,0,.9),(.065,.83,.13),'wood_dark')
 for x in [-.87,.87]:
  for y in [-.295,.25]:
   m.cyl('recessed_table_bolt',(x,y,.964),.015,.004,'steel_dark',sections=8)
 # hanging drawer under tabletop
 m.box('drawer_body',(0,-.365,.735),(.72,.16,.24),'wood_dark')
 m.box('drawer_face',(0,-.461,.735),(.70,.03,.21),'wood_light')
 m.box('drawer_pull',(0,-.487,.735),(.20,.026,.022),'steel')
 for x in [-.095,.095]: m.cyl('drawer_knob_pin',(x,-.50,.735),.017,.025,'steel_light','y',10)
 # clamp vise mounted left
 # bench vice, scaled down by VK about where it bolts onto the top (it was big enough to hide the radio)
 VK,VA=.6,np.array([-.75,-.23,.945])
 vp=lambda p:tuple(VA+(np.array(p)-VA)*VK)
 vs=lambda sz:tuple(v*VK for v in sz)
 m.box('vice_base',vp((-.75,-.23,1.01)),vs((.26,.20,.13)),'steel')
 m.box('vice_jaw_fixed',vp((-.75,-.16,1.11)),vs((.27,.045,.21)),'steel_dark')
 m.box('vice_jaw_mobile',vp((-.75,-.37,1.11)),vs((.27,.045,.21)),'steel')
 m.rod('vice_screw',vp((-.75,-.41,1.0)),vp((-.75,-.62,1.0)),.022*VK,'silver')
 m.rod('vice_handle',vp((-.86,-.62,1.0)),vp((-.64,-.62,1.0)),.018*VK,'steel_light')
 return m

def radio():
 # industrial HF base station (ham radio): a steel transceiver with rack handles, big tuning
 # knob, frequency readout and signal meter, stacked on a bench power supply with two analog
 # meters; hand mic on the side, coax up the wall to the roof antenna.
 # The story needs one 'speaker_panel' with 'speaker_grill_bar's (pulled out until the PA
 # speaker fixes it) and 'lcd_*' parts (they light up once it works).
 m=Model('HF base station (ham radio)')
 F=.015                                       # foot height
 PW,PD,PH=.44,.28,.10                         # power supply
 W,D,H=.50,.32,.17                            # transceiver, sitting on the supply
 back=D/2                                     # both units' backs line up
 # ---- power supply
 py=back-PD/2
 for x in [-.17,.17]:
  for y in [py-.10,py+.10]:m.box('rubber_foot',(x,y,F/2),(.05,.05,F),'black')
 pz=F+PH/2
 m.box('power_supply_case',(0,py,pz),(PW,PD,PH),'steel_dark')
 pf=py-PD/2-.005
 m.box('psu_front_panel',(0,pf,pz),(PW-.02,.01,PH-.016),'steel')
 for x in [-.13,-.03]:
  m.box('psu_meter_bezel',(x,pf-.008,pz+.005),(.085,.01,.065),'black')
  m.box('psu_meter_face',(x,pf-.014,pz+.005),(.07,.006,.048),'off_white')
  m.rod('psu_meter_needle',(x-.012,pf-.019,pz-.012),(x+.012,pf-.019,pz+.02),.003,'red')
 m.box('psu_power_switch',(.08,pf-.01,pz+.01),(.035,.016,.03),'red')
 m.cyl('psu_binding_post',(.14,pf-.012,pz-.015),.012,.02,'red','y',10)
 m.cyl('psu_binding_post',(.18,pf-.012,pz-.015),.012,.02,'black','y',10)
 # ---- transceiver
 z0=F+PH
 zc=z0+H/2
 m.box('transceiver_case',(0,0,zc),(W,D,H),'steel')
 for i in range(6):m.box('case_top_vent',(0,-.08+i*.035,z0+H+.002),(.30,.014,.004),'charcoal')
 for i in range(8):m.box('heatsink_fin',(-.175+i*.05,back+.012,zc),(.008,.024,H*.8),'steel_dark')
 yf=-D/2-.006                                  # front panel, and the parts mounted on it
 m.box('front_panel',(0,yf,zc),(W-.02,.012,H-.02),'steel_light')
 y1=yf-.009
 # speaker grill on the left
 m.box('speaker_panel',(-.165,y1,zc),(.13,.008,.13),'charcoal')
 for i in range(5):m.box('speaker_grill_bar',(-.165,y1-.006,zc-.05+i*.025),(.11,.008,.011),'steel_dark')
 # frequency readout and signal meter along the top
 m.box('readout_bezel',(.03,y1,zc+.04),(.19,.01,.055),'black')
 m.box('lcd_glass',(.03,y1-.006,zc+.04),(.16,.006,.032),'screen')
 for k in range(6):m.box('lcd_digit',(-.03+k*.024,y1-.01,zc+.04),(.014,.004,.02),'screen_dark')
 m.box('meter_bezel',(.185,y1,zc+.04),(.09,.01,.06),'black')
 m.box('meter_face',(.185,y1-.006,zc+.04),(.07,.006,.042),'off_white')
 m.rod('meter_needle',(.17,y1-.011,zc+.024),(.195,y1-.011,zc+.054),.003,'red')
 # big tuning knob, small knobs, switches
 m.cyl('vfo_knob_skirt',(.03,y1-.004,zc-.035),.048,.012,'silver','y',20)
 m.cyl('vfo_knob',(.03,y1-.025,zc-.035),.04,.035,'charcoal','y',20)
 m.cyl('vfo_finger_dimple',(.052,y1-.044,zc-.022),.008,.006,'steel','y',10)
 for x in [.15,.205]:
  m.cyl('control_knob_outer',(x,y1-.012,zc-.02),.019,.022,'charcoal','y',12)
  m.cyl('control_knob_center',(x,y1-.025,zc-.02),.008,.006,'brass','y',8)
 for k in range(3):m.rod('toggle_switch',(.135+k*.035,y1,zc-.062),(.135+k*.035,y1-.025,zc-.055),.005,'silver')
 m.box('power_switch',(-.065,y1-.006,zc+.04),(.03,.014,.028),'red')
 m.box('band_selector',(-.065,y1-.008,zc-.025),(.03,.016,.042),'orange')
 # rack handles on the front corners
 hy=yf-.045
 for x in [-W/2+.012,W/2-.012]:
  m.rod('front_handle',(x,yf,zc-.06),(x,hy,zc-.06),.009,'silver')
  m.rod('front_handle',(x,hy,zc-.06),(x,hy,zc+.06),.009,'silver')
  m.rod('front_handle',(x,hy,zc+.06),(x,yf,zc+.06),.009,'silver')
 # hand mic on a clip on the right side, its coiled cord down to the bench and into a side jack
 xs=W/2
 m.box('mic_hanger_clip',(xs+.006,-.06,zc+.045),(.012,.025,.03),'steel_dark')
 m.box('hand_mic',(xs+.025,-.06,zc-.005),(.035,.05,.085),'black')
 m.box('mic_ptt_button',(xs+.044,-.06,zc+.005),(.006,.018,.03),'steel_light')
 m.cyl('mic_jack',(xs+.004,-.12,zc-.05),.01,.012,'brass','x',8)
 cord=[(xs+.025,-.06,zc-.05),(xs+.035,-.08,F+.04),(xs+.02,-.10,F+.02),(xs+.035,-.115,F+.05),(xs+.006,-.12,zc-.05)]
 for a,b in zip(cord,cord[1:]):m.rod('mic_cord',a,b,.006,'black')
 # coax from the rear connector up the wall into the ceiling beam (roof antenna), clipped on the way
 cx,cy=-.23,back+.034
 m.cyl('coax_connector',(cx,back+.012,zc+.03),.012,.024,'brass','y',10)
 m.rod('coax_cable',(cx,back+.024,zc+.03),(cx,cy,zc+.07),.007,'black')
 m.rod('coax_cable',(cx,cy,zc+.07),(cx,cy,2.0),.007,'black')
 for z in [.8,1.4]:m.box('coax_clip',(cx,cy+.004,z),(.03,.012,.02),'steel_light')
 return m

def microfiche_reader():
 # wall-mounted microfiche display, hung where the paper map was: a map-sized rear-projection
 # screen in a wooden map frame on a shallow steel housing, with a control strip below (fiche card
 # pocket, focus and scan knobs). Heights are absolute (screen centre at Z0) and the back sits on
 # the wall, so the scene places it with y_back and no surface. The game draws a turning globe on
 # 'fiche_screen' while it is idle; nothing else may use an emissive keyword (screen, lcd, display,
 # lens, flame).
 m=Model('Wall-mounted microfiche display')
 Z0=2.02
 W,H=.78,.54                                  # screen
 m.box('viewer_housing',(0,.16,Z0),(W+.04,.08,H+.04),'steel_dark')
 m.frame('map_frame',W+.10,H+.10,(0,.11,Z0),.05,.035,'walnut')
 m.box('fiche_screen',(0,.118,Z0),(W,.008,H),'screen')
 m.box('frame_label_plate',(0,.091,Z0-H/2-.025),(.14,.006,.022),'brass')
 for x in [-.30,.30]:m.box('hanging_bracket',(x,.18,Z0+H/2+.07),(.04,.04,.06),'steel')
 zc=Z0-H/2-.05-.07                            # control strip, just under the frame
 m.box('control_strip',(0,.16,zc),(.50,.08,.12),'steel')
 m.box('fiche_card',(.13,.118,zc),(.13,.004,.085),'navy')
 m.box('fiche_card_header',(.13,.115,zc+.03),(.13,.005,.014),'off_white')
 for x in [-.18,-.10]:m.cyl('focus_knob',(x,.11,zc),.022,.02,'black','y',12)
 m.box('power_switch',(-.02,.116,zc+.02),(.03,.015,.02),'red')
 m.box('status_light',(-.02,.116,zc-.025),(.012,.012,.012),'aqua')
 return m

def cabinet(open_state=False):
 m=Model('Supply cabinet '+('open' if open_state else 'closed'))
 m.box('cabinet_shell',(0,.0,1.02),(1.17,.54,1.83),'cream_shadow')
 m.box('inset_dark_interior',(0,-.281,1.03),(1.03,.008,1.64),'wood_darkest')
 # internal shelves
 for z in [.45,.91,1.39]:
  m.box('interior_shelf',(0,-.08,z),(1.04,.42,.048),'wood_light')
 m.box('thick_top_cap',(0,0,1.97),(1.30,.65,.12),'walnut_light')
 m.box('bottom_plinth',(0,0,.102),(1.22,.60,.14),'wood_dark')
 for x in [-.515,.515]:m.box('cabinet_side_trim',(x,-.29,1.015),(.058,.053,1.71),'walnut')
 # products appear when open
 if open_state:
  for x,z,r,h,c in [(-.33,.57,.075,.15,'steel'),(-.1,.56,.065,.17,'red'),(.20,.56,.07,.16,'steel'),(-.27,1.02,.09,.15,'aqua'),(.16,1.06,.105,.22,'olive'),(-.24,1.57,.07,.22,'steel'),(.21,1.55,.09,.23,'canvas')]:
   m.cyl('supply_tin_or_canister',(x,-.16,z),r,h,c,sections=10)
 # doors closed flush or opened to the side (yaw around outboard hinge)
 for side in (-1,1):
  cx=side*.275
  if not open_state:
   m.box('removable_door_panel',(cx,-.323,1.05),(.52,.07,1.68),'wood_light')
   for i in range(3):m.box('door_vertical_plank_seam',(cx+(i-1)*.128,-.365,1.05),(.014,.007,1.54),'wood_dark')
   m.frame('door_inset_trim',.46,1.60,(cx,-.364,1.05),.041,.02,'walnut')
   m.cyl('door_pull', (side*.10,-.40,1.05),.025,.063,'brass','y',12)
   m.box('keyhole',(side*.10,-.431,1.0),(.014,.004,.025),'steel_dark')
  else:
   # 90deg open toward viewer, side-mounted doors
   x=side*.58
   m.box('open_door_panel',(x,-.60,1.05),(.075,.52,1.68),'wood_light')
   m.box('open_door_stile',(x-side*.007,-.60,1.05),(.086,.46,1.55),'walnut_light')
   m.cyl('open_door_pull',(x-side*.025,-.82,1.05),.023,.06,'brass','x',10)
  for z in [.45,1.65]:
   m.box('hinge_leaf',(side*.578,-.32 if not open_state else -.38,z),(.025,.06,.125),'steel')
   m.cyl('hinge_pin',(side*.59,-.30,z),.011,.15,'brass',sections=8)
 return m

def power_station():
 m=Model('Portable power station')
 m.box('main_enclosure',(0,0,.33),(.71,.36,.58),'olive')
 m.box('top_recess',(0,0,.611),(.60,.29,.03),'olive_light')
 m.box('front_bezel',(0,-.191,.336),(.63,.025,.47),'steel_dark')
 m.box('control_panel',(0,-.207,.340),(.57,.011,.415),'charcoal')
 for x in [-.31,.31]:
  for z in [.137,.544]:m.cyl('panel_mount_screw',(x,-.222,z),.009,.01,'silver','y',8)
 m.box('LCD_outer',(0,-.220,.438),(.37,.012,.153),'steel')
 m.box('LCD_inner',(0,-.230,.437),(.323,.009,.117),'screen_dark')
 for i in range(5):
  m.box('battery_charge_segment',(-.12+i*.056,-.237,.437),(.044,.009,.053),'screen_glow' if i<4 else 'screen')
 m.box('display_readout',(0,-.238,.385),(.24,.005,.009),'aqua')
 for x in [-.19,0,.19]:
  m.cyl('output_socket_recess',(x,-.232,.230),.063,.016,'steel','y',14)
  m.cyl('output_socket_dark_center',(x,-.245,.230),.038,.006,'black','y',12)
 for x in [-.10,.10]:
  m.box('USB_port',(x,-.239,.146),(.072,.009,.020),'steel_light')
  m.box('USB_dark_slot',(x,-.249,.146),(.051,.006,.012),'black')
 m.cyl('on_off_button',(.26,-.239,.364),.029,.019,'red','y',12)
 # sturdy handle
 for x in [-.21,.21]:m.box('handle_upright',(x,0,.70),(.060,.067,.17),'graphite')
 m.box('handle_grip',(0,0,.790),(.49,.075,.058),'steel_dark')
 for x in [-.28,.28]:
  for y in [-.13,.13]:m.box('shock_foot',(x,y,.022),(.105,.07,.044),'black')
 # side ventilation slits
 for side in [-1,1]:
  for i in range(4):m.box('cooling_vent',(side*.363,-.075+i*.052,.39),(.007,.023,.115),'olive_dark')
 return m

def storm_shutters(open_state=False):
 m=Model('Storm shutters '+('stowed' if open_state else 'secured'))
 # two panels that together cover the whole 3.24 x 1.10 m window opening (inside the jambs,
 # sill and lintel of build_pixel_scene.py) with a little overlap; z centre 1.53
 PW,PH,CZ=1.62,1.14,1.53
 bottom=CZ-PH/2
 for side in (-1,1):
  if not open_state: center_x=side*PW/2; yy=-.08
  else: center_x=side*2.30; yy=-.08
  m.box('shutter_backing',(center_x,yy,CZ),(PW,.08,PH),'wood_dark')
  n=8
  for i in range(n):
   z=bottom+.04+(i+.5)*(PH-.08)/n
   m.box('horizontal_storm_slats',(center_x,yy-.048,z),(PW-.02,.055,(PH-.08)/n-.012),'wood_light' if i%2 else 'oak')
  for dx in [-(PW/2-.045),PW/2-.045]:m.box('side_framing',(center_x+dx,yy-.075,CZ),(.075,.070,PH+.04),'walnut')
  m.box('top_crossbar',(center_x,yy-.076,bottom+PH-.035),(PW-.06,.065,.073),'walnut')
  m.box('bottom_crossbar',(center_x,yy-.076,bottom+.035),(PW-.06,.065,.074),'walnut')
  m.box('center_reinforcement',(center_x,yy-.11,CZ-.02),(PW-.08,.045,.105),'wood_dark')
  for z in [bottom+.22,bottom+PH-.22]:
   hinge_x=center_x+side*(PW/2-.005)
   m.box('heavy_hinge',(hinge_x,yy-.13,z),(.16,.05,.135),'steel')
   m.cyl('steel_hinge_bolt',(hinge_x,yy-.16,z),.025,.035,'brass','y')
  m.box('sliding_latch',(center_x-side*(PW/2-.21),yy-.16,CZ),(.21,.045,.06),'steel_dark')
  m.cyl('latch_rivet',(center_x-side*(PW/2-.21),yy-.19,CZ),.021,.017,'steel_light','y')
 return m

def sandbags():
 m=Model('Stacked sandbag flood barrier')
 # x wide, arranged in overlapping layers
 for level in range(3):
  n=5-level
  xstart=-(n-1)*.235
  for k in range(n):
   x=xstart+k*.47 + (.095 if level==1 else 0)
   y=-.01 + (k%2)*.019
   z=.12+level*.19
   tint=['canvas','canvas_light','canvas_dark','canvas','cream_shadow'][(k+level*2)%5]
   body=trimesh.creation.icosphere(subdivisions=1,radius=1)
   body.apply_scale([.259,.175,.112])
   body.apply_translation([x,y,z])
   m.add(body,'stuffed_burlap_bag',tint)
   # stitch/seam across forward face
   m.box('stitched_upper_edge',(x,-.137,z+.022),(.39,.012,.012),'canvas_dark')
   for sx in [-.16,-.08,0,.08,.16]:
    m.box('seam_cross_stitch',(x+sx,-.15,z+.022),(.008,.012,.019),'wood_pale')
   if k%3==0:
    m.sphere('tied_sack_knot',(x+.255,.0,z),(.041,.044,.032),'canvas_dark',1)
 return m

def water_filter():
 m=Model('Gravity-fed water filtration rig')
 # tripod-ish braced stand and two stacked canisters
 for x in [-.265,.265]:
  for y in [-.17,.17]:
   m.box('support_frame_leg',(x,y,.62),(.042,.042,1.18),'steel_dark')
 for z in [.20,.71,1.13]:
  m.box('stand_crossbar_left_to_right',(0,-.165,z),(.57,.04,.035),'steel')
  m.box('stand_crossbar_depth',(.265,0,z),(.04,.34,.035),'steel')
 m.cyl('upper_filter_tank',(0,0,1.14),.241,.50,'navy',sections=16)
 m.cyl('upper_tank_lid',(0,0,1.403),.258,.044,'graphite',sections=16)
 m.cyl('lid_dome',(0,0,1.445),.09,.047,'steel',sections=10)
 m.cyl('lower_collecting_tank',(0,0,.465),.21,.41,'steel_light',sections=16)
 m.cyl('collector_lid',(0,0,.680),.226,.035,'metal',sections=16)
 m.cyl('collector_base',(0,0,.25),.225,.029,'steel_dark',sections=16)
 m.cyl('tank_filter_stage',(0,0,.82),.118,.18,'cream',sections=12)
 m.cone('filter_narrowing',(0,0,.735),.10,.13,.09,'steel',sections=12)
 m.rod('water_tube',(0,0,.71),(0,0,.67),.037,'navy')
 # spigot protrudes forward
 m.rod('tap_outlet',(0,-.20,.38),(0,-.37,.38),.031,'brass')
 m.cyl('water_tap_handle',(0,-.30,.435),.062,.018,'steel_dark',sections=8)
 m.rod('spout_down',(0,-.37,.38),(0,-.37,.30),.020,'brass')
 m.box('water_level_window',(0,-.240,1.18),(.075,.018,.22),'steel_light')
 m.box('water_level_blue',(0,-.254,1.13),(.041,.010,.105),'aqua')
 # collection bucket to one side under nozzle
 m.cone('portable_basin',(.48,-.32,.14),.15,.18,.27,'olive_light',sections=12)
 m.ring('basin_rim',(.48,-.32,.27),.182,.148,.021,'steel',sections=16)
 m.rod('basin_handle_left',(.32,-.32,.22),(.34,-.32,.34),.012,'steel')
 m.rod('basin_handle_top',(.34,-.32,.34),(.64,-.32,.34),.012,'steel')
 m.rod('basin_handle_right',(.64,-.32,.34),(.66,-.32,.22),.012,'steel')
 return m

def weather_instruments():
 m=Model('Wall mounted instruments')
 # hanging board, bottom 1.32 top 1.9
 m.box('oak_mounting_board',(0,.032,1.58),(.98,.09,.54),'walnut')
 m.box('weather_station_face',(0,-.022,1.58),(.91,.03,.48),'wood_light')
 for x in [-.43,.43]:
  for z in [1.37,1.79]:m.cyl('panel_wood_screw',(x,-.046,z),.012,.011,'brass','y',8)
 # circle dials in x-z plane, face points toward -Y
 for idx,xc in enumerate([-.25,.085]):
  zc=1.59
  m.cyl('analog_gauge_metal_rim',(xc,-.063,zc),.161,.041,'brass','y',24)
  m.cyl('analog_dial_face',(xc,-.086,zc),.132,.009,'off_white','y',24)
  for t in range(11):
   a=math.radians(-140+t*28)
   x=xc+.104*math.sin(a); z=zc+.104*math.cos(a)
   m.rod('radial_tick',(x-.011*math.sin(a),-.095,z-.011*math.cos(a)),
         (x+.011*math.sin(a),-.095,z+.011*math.cos(a)),.0035,'graphite',6)
  angle=(-.48 if idx==0 else .30)
  m.rod('dark_gauge_pointer',(xc,-.100,zc),(xc+.087*math.sin(angle),-.100,zc+.087*math.cos(angle)),.010,'steel_dark')
  m.cyl('center_needle_hub',(xc,-.108,zc),.018,.019,'brass','y',10)
 # long thermometer
 m.box('thermo_backing',(.355,-.072,1.59),(.13,.035,.364),'steel_dark')
 m.box('thermo_white_scale',(.355,-.095,1.59),(.080,.010,.308),'off_white')
 m.box('mercury_tube',(.34,-.106,1.59),(.016,.009,.245),'glass')
 m.box('mercury_fill',(.34,-.114,1.53),(.014,.011,.12),'red')
 m.sphere('thermometer_bulb',(.34,-.114,1.464),(.026,.015,.026),'red',1)
 for i in range(6):
  zz=1.485+i*.043
  m.box('thermometer_scale_mark',(.369,-.107,zz),(.021,.007,.006),'steel_dark')
 return m

def single_crate(m,tag,center,dim,open_top=False):
 cx,cy,z0=center
 w,d,h=dim
 # bottom and inner cavity wall
 m.box(tag+'_bottom',(cx,cy,z0+.045),(w,d,.09),'wood_dark')
 if not open_top:m.box(tag+'_lid',(cx,cy,z0+h-.045),(w,d,.09),'oak')
 for ysign in [-1,1]:
  y=cy+ysign*(d/2-.024)
  for i in range(4):
   zh=z0 + (i+.5)*(h-.12)/4+.06
   m.box(tag+'_front_back_plank',(cx,y,zh),(w-.055,.056,(h-.14)/4-.012),'oak_alt' if i%2 else 'wood_light')
 for xsign in [-1,1]:
  x=cx+xsign*(w/2-.03)
  for i in range(3):
   zh=z0+(i+.5)*(h-.1)/3+.05
   m.box(tag+'_side_plank',(x,cy,zh),(.065,d-.06,(h-.13)/3-.014),'wood')
 for xsign in [-1,1]:
  for ysign in [-1,1]:
   x=cx+xsign*(w/2-.05); y=cy+ysign*(d/2-.05)
   m.box(tag+'_metal_corner',(x,y,z0+h/2),(.070,.070,h),'wood_dark')
   for zz in [z0+.12,z0+h-.11]:
    m.cyl(tag+'_corner_rivet',(x, y-ysign*.043,zz),.011,.011,'brass','y',8)
 # diagonal brace at front
 m.rod(tag+'_diagonal_reinforcement',(cx-w*.36,cy-d*.5-.028,z0+.09),
       (cx+w*.36,cy-d*.5-.028,z0+h-.10),.022,'wood_dark')
 if open_top:
  for xx,color in [(-.19,'metal'),(-.01,'red'),(.19,'olive')]:
   m.cyl(tag+'_food_tin',(cx+xx,cy,z0+h-.05),.077,.31,color,sections=12)
   m.cyl(tag+'_food_tin_lid',(cx+xx,cy,z0+h+.113),.080,.014,'silver',sections=12)

def crates():
 m=Model('Emergency supply crates')
 single_crate(m,'bottom_left',(-.45,.045,0),(.74,.54,.52),False)
 single_crate(m,'bottom_right',(.40,.035,0),(.70,.55,.43),True)
 single_crate(m,'top_crate',(-.33,.060,.52),(.52,.43,.36),False)
 return m

def lantern():
 m=Model('Emergency kerosene lantern')
 m.cyl('lantern_foot',(0,0,.035),.145,.067,'steel_dark',sections=16)
 m.cone('fuel_reservoir',(0,0,.126),.125,.104,.13,'olive_dark',sections=16)
 m.ring('base_brass_trim',(0,0,.19),.12,.093,.03,'brass',sections=16)
 # glowing glass chimney solid for silhouette; bronze outer cage
 m.cyl('glass_lantern_chamber',(0,0,.34),.087,.275,'glass',sections=12)
 m.cyl('interior_flame_glow',(0,0,.29),.036,.127,'yellow',sections=8)
 m.cone('burner_flame',(0,0,.367),.028,0.001,.096,'orange',sections=8)
 m.ring('chamber_lower_guard',(0,0,.215),.11,.083,.026,'steel_dark',sections=16)
 m.ring('chamber_top_guard',(0,0,.475),.11,.075,.033,'steel_dark',sections=16)
 for a in [0,math.pi/2,math.pi,math.pi*1.5]:
  x=.104*math.cos(a); y=.104*math.sin(a)
  m.rod('wire_protective_guard',(x,y,.226),(x,y,.485),.013,'steel_dark')
 m.cone('chimney',(0,0,.54),.125,.087,.115,'olive_dark',sections=12)
 m.cyl('vent_cap',(0,0,.610),.111,.043,'graphite',sections=12)
 # C shaped carrying handle as connected segments
 handle=[(-.115,0,.59),(-.15,0,.75),(-.09,0,.81),(0,0,.83),(.09,0,.81),(.15,0,.75),(.115,0,.59)]
 for i in range(len(handle)-1):m.rod('foldable_arched_handle',handle[i],handle[i+1],.015,'steel')
 m.cyl('brightness_knob',(.153,-.06,.128),.035,.038,'brass','x',12)
 return m

def flashlight():
 m=Model('Battery-powered flashlight')
 # length on X, solid glass lens facing +X, slight downward angle not necessary
 m.cyl('main_flashlight_body',(0,0,.102),.087,.43,'graphite','x',sections=12)
 m.cyl('tail_cap',(-.225,0,.102),.099,.055,'steel_dark','x',sections=12)
 m.cone('torch_head_flared',(.255,0,.102),.088,.143,.19,'olive_dark','x',sections=12)
 m.ring('lens_metal_bezel',(.358,0,.102),.148,.12,.049,'steel_light','x',sections=16)
 m.cyl('yellowish_lens',(.385,0,.102),.119,.011,'screen_glow','x',sections=16)
 m.cyl('central_emitter',(.396,0,.102),.042,.016,'off_white','x',sections=16)
 for x in [-.15,-.105,-.06,-.015,.03,.075]:
  m.ring('rubber_grip_rib',(x,0,.102),.090,.086,.013,'steel_dark','x',sections=12)
 m.box('rubber_power_button',(0,0,.196),(.10,.09,.026),'red')
 m.box('wrist_strap_anchor',(-.26,0,.1),(.044,.043,.06),'steel')
 return m

BUILDERS = [
 ('01_wooden_workbench',workbench),
 ('02_emergency_weather_radio',radio),
 ('03_supply_cabinet_closed',cabinet),
 ('04_portable_power_station',power_station),
 ('05_storm_shutters_closed',storm_shutters),
 ('06_sandbag_flood_barrier',sandbags),
 ('07_gravity_water_filter',water_filter),
 ('08_wall_weather_instruments',weather_instruments),
 ('09_supply_crates',crates),
 ('10_emergency_lantern',lantern),
 ('11_flashlight',flashlight),
 ('12_supply_cabinet_open',lambda: cabinet(True)),
 ('13_storm_shutters_stowed',lambda: storm_shutters(True)),
 ('14_microfiche_reader',microfiche_reader),
]

if __name__=='__main__':
 bounds={}
 for name,builder in BUILDERS:
  ob=builder()
  ob.export(name)
  bounds[name]={'parts':ob.seq,'bounds':ob.scene.bounds.tolist()}
 (ROOT/'asset_manifest.json').write_text(json.dumps({
  'orientation':'Z up, front toward -Y, meters',
  'format':'binary glTF 2.0 (GLB), mesh and materials included',
  'assets':bounds},indent=2))
