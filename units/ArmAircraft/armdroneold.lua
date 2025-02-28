return {
	armdroneold = {
		blocking = false,
		buildpic = "ARMKAM.DDS",
		buildtime = 2200,
		canfly = true,
		canmove = true,
		collide = true,
		cruisealtitude = 70,
		energycost = 1100,
		explodeas = "smallExplosionGeneric",
		footprintx = 2,
		footprintz = 2,
		health = 400,
		hoverattack = true,
		idleautoheal = 0,
		idletime = 1800,
		maxacc = 0.2,
		maxdec = 0.45,
		maxslope = 10,
		maxwaterdepth = 0,
		metalcost = 55,
		nochasecategory = "VTOL",
		objectname = "Units/ARMDRONEOLD.s3o",
		script = "Units/ARMDRONEOLD.cob",
		seismicsignature = 0,
		selfdestructas = "smallExplosionGenericSelfd",
		sightdistance = 520,
		speed = 225,
		turninplaceanglelimit = 360,
		turnrate = 900,
		customparams = {
			drone = 1,
			model_author = "FireStorm",
			normaltex = "unittextures/Arm_normal.dds",
			subfolder = "ArmAircraft",
			unitgroup = "weapon",
		},
		sfxtypes = {
			crashexplosiongenerators = {
				[1] = "crashing-small",
				[2] = "crashing-small",
				[3] = "crashing-small2",
				[4] = "crashing-small3",
				[5] = "crashing-small3",
			},
			pieceexplosiongenerators = {
				[1] = "airdeathceg2",
				[2] = "airdeathceg3",
				[3] = "airdeathceg4",
			},
		},
		sounds = {
			canceldestruct = "cancel2",
			underattack = "warning1",
			cant = {
				[1] = "cantdo4",
			},
			count = {
				[1] = "count6",
				[2] = "count5",
				[3] = "count4",
				[4] = "count3",
				[5] = "count2",
				[6] = "count1",
			},
			ok = {
				[1] = "vtolarmv",
			},
			select = {
				[1] = "vtolarac",
			},
		},
		weapondefs = {
			med_emg = {
				accuracy = 13,
				areaofeffect = 16,
				avoidfeature = false,
				burnblow = false,
				burst = 3,
				burstrate = 0.105,
				craterareaofeffect = 0,
				craterboost = 0,
				cratermult = 0,
				duration = 0.035,
				edgeeffectiveness = 0.5,
				explosiongenerator = "blank",
				impulsefactor = 0.123,
				intensity = 0.8,
				name = "Rapid-fire a2g machine guns",
				noselfdamage = true,
				ownerexpaccweight = 2,
				range = 350,
				reloadtime = 1.65,
				rgbcolor = "1 0.95 0.4",
				soundhit = "bimpact3",
				soundhitwet = "splshbig",
				soundstart = "mgun3",
				sprayangle = 1024,
				thickness = 0.9,
				tolerance = 6000,
				turret = false,
				weapontype = "LaserCannon",
				weaponvelocity = 800,
				damage = {
					commanders = 5,
					default = 11,
					vtol = 1,
				},
			},
			railgun = {
				areaofeffect = 8,
				avoidfeature = false,
				burnblow = false,
				cegtag = "railgun",
				craterareaofeffect = 0,
				craterboost = 0,
				cratermult = 0,
				duration = 0.06,
				edgeeffectiveness = 0.85,
				explosiongenerator = "custom:plasmahit-sparkonly",
				falloffrate = 0.2,
				firestarter = 0,
				impulsefactor = 1,
				intensity = 0.8,
				name = "Railgun",
				noselfdamage = true,
				ownerexpaccweight = 4,
				proximitypriority = 1,
				range = 350,
				reloadtime = 6,
				rgbcolor = "0.34 0.64 0.94",
				soundhit = "mavgun3",
				soundhitwet = "splshbig",
				soundstart = "railgun3",
				soundstartvolume = 13,
				thickness = 1.5,
				tolerance = 6000,
				turret = false,
				weapontype = "LaserCannon",
				weaponvelocity = 2000,
				damage = {
					default = 100,
				},
			},
		},
		weapons = {
			[1] = {
				badtargetcategory = "VTOL",
				def = "RAILGUN",
				onlytargetcategory = "NOTSUB",
			},
		},
	},
}
