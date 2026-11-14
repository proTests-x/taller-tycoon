"""Asset-free four-plot Garage Tycoon map for the Roblox place builder."""


def create_scene():
    parts = []
    navy = [30, 48, 72]
    teal = [47, 210, 180]
    gold = [255, 198, 62]
    cream = [230, 235, 224]
    purple = [166, 103, 255]
    plot_origins = [(-55, -55), (55, -55), (-55, 55), (55, 55)]

    def part(name, position, size, color, material="SmoothPlastic", **kwargs):
        data = dict(name=name, position=list(position), size=list(size), color=color, material=material)
        data.update(kwargs)
        parts.append(data)
        return data

    def sign(name, pos, size, text, fg=cream, bg=navy, face="Front"):
        return part(name, pos, size, bg, surfaces=[dict(face=face, text=text, textColor=fg, backgroundColor=bg, textSize=44)])

    part("IslandGround", (0, -1.3, 0), (235, 1, 260), [89, 151, 111], "Grass")
    part("NorthSouthRoad", (0, -.45, 0), (21, .8, 245), [49, 64, 81], "Asphalt")
    part("CrossRoad", (0, -.45, 0), (214, .8, 20), [49, 64, 81], "Asphalt")
    part("EntranceRoad", (0, -.45, -96), (198, .8, 14), [49, 64, 81], "Asphalt")
    for z in range(-114, 119, 12):
        part("RoadStripe", (0, -.025, z), (.35, .035, 5), gold)
    for x in range(-102, 103, 12):
        part("CrossStripe", (x, -.025, 0), (5, .035, .3), gold)
    for x in (-11.3, 11.3):
        part("CentralPavement", (x, -.25, -1), (1.5, 1, 245), [183, 203, 199], "Concrete")
    part("WelcomePlaza", (0, 0, -111), (42, 1, 22), [182, 204, 211], "Concrete")
    part("WelcomeInset", (0, .52, -110), (28, .045, 13), navy)
    for x in (-18, 18):
        part("WelcomePillar", (x, 5.5, -118), (.8, 11, .8), navy, "Metal")
        part("WelcomePillarLight", (x, 5, -118.5), (.2, 7, .1), teal, "Neon")
    sign("WelcomeTitle", (0, 10.4, -118), (38, 3.2, .7), "TALLER TYCOON", fg=teal)
    sign("WelcomeSubtitle", (0, 7.8, -118.45), (28, 1.2, .25), "MONEDAS  >  AUTOS  >  RENACER", fg=gold)
    sign("WelcomeFloorSign", (0, .57, -110), (24, .06, 8), "TU PRÓXIMO AUTO\nEMPIEZA CON UNA MONEDA", fg=cream, face="Top")

    plot_metadata = []
    for index, (ox, oz) in enumerate(plot_origins, 1):
        prefix = f"Plot{index}"
        accent = [teal, [71, 167, 250], [245, 173, 66], [181, 118, 247]][index - 1]

        def p(name, xyz, size, color, material="SmoothPlastic", **kwargs):
            return part(prefix + name, (ox + xyz[0], xyz[1], oz + xyz[2]), size, color, material, **kwargs)

        def s(name, xyz, size, text, fg=cream, bg=navy, face="Front"):
            return sign(prefix + name, (ox + xyz[0], xyz[1], oz + xyz[2]), size, text, fg, bg, face)

        p("Origin", (0, .5, 0), (.2, .2, .2), accent, transparency=1, canCollide=False)
        p("Floor", (0, 0, 0), (64, 1, 62), [205, 215, 211], "Concrete")
        p("FrontApron", (0, -.02, -34), (58, .9, 7), [124, 149, 155], "Concrete")
        p("EntranceMat", (0, .535, -27.5), (18, .05, 5), accent)
        p("BackWall", (0, 4.7, 30.5), (64, 8.4, .6), cream, "Concrete")
        p("BackWallStripe", (0, 1.65, 30.12), (63, 1.5, .16), accent)
        p("WestWall", (-31.7, 2.3, 8.5), (.6, 3.6, 44), cream, "Concrete")
        p("EastWall", (31.7, 2.3, 8.5), (.6, 3.6, 44), cream, "Concrete")
        for x in (-31, 31):
            for z in (-8, 29):
                p("Column", (x, 5.5, z), (.65, 10, .65), navy, "Metal")
                p("ColumnAccent", (x, 4.2, z - .37), (.3, 6, .12), accent, "Neon")
        p("RearCanopy", (0, 10.3, 23), (64, .35, 15), navy, "Metal")
        p("RearCanopyEdge", (0, 10.2, 15.4), (64, .22, .25), accent, "Neon")
        p("FrontBeam", (0, 10.3, -8), (64, .5, .6), navy, "Metal")
        for x in (-24, 0, 24):
            p("CanopyLamp", (x, 9.95, 23), (4, .15, .75), [255, 236, 188], "Neon", pointLight=dict(color=[255, 234, 192], brightness=.35, range=22))
        s("GarageLogo", (0, 7, 30.08), (20, 2.4, .2), "MI COLECCIÓN", fg=navy, bg=cream)
        s("GarageSteps", (0, 4.7, 30.06), (22, 1.2, .2), "COMPRA  •  GANA  •  MEJORA", fg=[65, 105, 113], bg=cream)
        s("PlotNumber", (-28, 6.5, 30.08), (4, 3, .2), f"0{index}", fg=accent)

        for tier in range(1, 7):
            col = (tier - 1) % 3
            row = (tier - 1) // 3
            bx, bz = (-20, 0, 20)[col], (0, 19)[row]
            p(f"Bay{tier}Floor", (bx, .56, bz), (12.3, .12, 14.4), [54, 72, 91], "Metal")
            for dx in (-6.15, 6.15):
                p("BayOutline", (bx + dx, .64, bz), (.12, .08, 14.4), accent, "Neon", canCollide=False)
            for dz in (-7.2, 7.2):
                p("BayOutline", (bx, .64, bz + dz), (12.3, .08, .12), accent, "Neon", canCollide=False)
            p(f"Bay{tier}Origin", (bx, .7, bz), (.2, .2, .2), accent, transparency=1, canCollide=False)
            p("BayStop", (bx, .85, bz + 6.4), (6.3, .35, .5), gold, "Metal")
            s(f"Bay{tier}Number", (bx, .67, bz + 5.5), (3, .03, 1.2), f"0{tier}", fg=[123, 154, 174], face="Top")

        p("CoinField", (0, .535, -18), (47, .05, 16), [174, 201, 191])
        for x in (-23.5, 23.5):
            p("CoinFieldEdge", (x, .59, -18), (.14, .05, 16), gold, "Neon", canCollide=False)
        for z in (-26, -10):
            p("CoinFieldEdge", (0, .59, z), (47, .05, .14), gold, "Neon", canCollide=False)
        for cx in (-21, -7, 7, 21):
            for cz in (-24, -18, -12):
                p("CoinSpot", (cx, .58, cz), (.065, 2.7, 2.7), [234, 215, 140], "Metal", shape="Cylinder", rotation=[0, 0, 90], canCollide=False)

        p("UpgradeLane", (28.7, .56, -5.5), (4.5, .1, 39), [68, 87, 111], "Metal")
        s("UpgradeHeader", (28.7, 6.2, 13), (5.5, 1.2, .2), "MEJORAS", fg=gold)
        p("RebirthPlatform", (-28.7, .73, -17), (5, .45, 7), [80, 56, 125], "Metal")
        for x in (-30.7, -26.7):
            p("PortalPillar", (x, 3.4, -17), (.4, 5.6, .6), purple, "Neon", pointLight=dict(color=purple, brightness=.25, range=12))
        p("PortalTop", (-28.7, 6.1, -17), (4.4, .5, .6), purple, "Neon")
        p("PortalGlow", (-28.7, 3.4, -17), (3.6, 5, .1), purple, "ForceField", transparency=.75, canCollide=False)
        s("RebirthHeader", (-28.7, 7.4, -17), (6, 1.2, .25), "RENACER", fg=[226, 200, 255])

        p("ToolCabinet", (-28.5, 2, 21), (4, 2.8, 2.3), accent, "Metal")
        for y in (1.2, 1.9, 2.6):
            p("ToolDrawer", (-28.5, y, 19.8), (3.7, .5, .1), [39, 81, 92], "Metal")
            p("DrawerHandle", (-28.5, y, 19.68), (1.5, .08, .12), cream, "Metal")
        for x, z in ((-29, -29), (29, -29)):
            p("EntryBollard", (x, 1.6, z), (.5, 2.2, .5), navy, "Metal")
            p("EntryBollardTop", (x, 2.8, z), (.6, .2, .6), accent, "Neon")
        plot_metadata.append(dict(index=index, origin=[ox, .5, oz], entry=[ox, 3.5, oz - 28]))

    for x, z in ((-104, -84), (104, -84), (-104, 32), (104, 32), (-93, 108), (93, 108), (-18, 108), (18, 108)):
        part("TreeTrunk", (x, 2.5, z), (1, 5, 1), [104, 85, 63], "Wood")
        part("TreeCrown", (x, 6.2, z), (8, 7, 8), [53, 119, 84], shape="Ball")
        part("TreeCrownLight", (x - 1.4, 8.2, z - .5), (6, 5, 6), [73, 142, 97], shape="Ball")
    for x, z in ((-15, -42), (15, -42), (-15, 52), (15, 52), (-42, -10), (42, 10)):
        part("StreetlampPole", (x, 6, z), (.35, 12, .35), navy, "Metal")
        part("StreetlampHead", (x, 12, z), (2, .25, 2), [255, 225, 172], "Neon", pointLight=dict(color=[255, 227, 181], brightness=.4, range=26))
    for z in (-74, 73):
        for x in (-15.8, 15.8):
            part("Planter", (x, .4, z), (3, 1, 10), navy, "Concrete")
            part("PlanterHedge", (x, 1.4, z), (2.6, 1.4, 9.5), [64, 129, 92], "Grass")
    part("PerimeterWest", (-117, 1, 0), (1, 4, 260), [91, 128, 124], "Concrete")
    part("PerimeterEast", (117, 1, 0), (1, 4, 260), [91, 128, 124], "Concrete")
    part("PerimeterBack", (0, 1, 129), (235, 4, 1), [91, 128, 124], "Concrete")
    part("PerimeterFront", (0, 1, -129), (235, 4, 1), [91, 128, 124], "Concrete")

    return {
        "parts": parts,
        "plots": plot_metadata,
        "spawn": {"position": [0, 1.1, -110], "rotation": [0, 180, 0]},
        "lighting": {"clockTime": 16.6, "brightness": 2, "ambient": [110, 120, 138], "outdoorAmbient": [143, 146, 160], "fogColor": [179, 205, 229], "fogStart": 280, "fogEnd": 750},
    }
