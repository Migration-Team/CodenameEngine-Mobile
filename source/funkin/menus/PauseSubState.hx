package funkin.menus;

import funkin.editors.charter.Charter;
import funkin.backend.scripting.events.MenuChangeEvent;
import funkin.options.OptionsMenu;
import funkin.backend.scripting.events.PauseCreationEvent;
import funkin.backend.scripting.events.NameEvent;
import funkin.backend.scripting.Script;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.options.keybinds.KeybindsOptions;
import funkin.menus.StoryMenuState;
import funkin.backend.utils.FunkinParentDisabler;
import flixel.util.FlxTimer;

class PauseSubState extends MusicBeatSubstate
{
	public static var script:String = "";

	var grpMenuShit:FlxTypedGroup<Alphabet>;

	var menuItems:Array<String> = ['Resume', 'Restart Song', 'Change Controls', 'Change Options', 'Exit to menu', "Exit to charter"];
	var curSelected:Int = 0;

	var pauseMusic:FlxSound;

	public var pauseScript:Script;

	public var game:PlayState = PlayState.instance; // shortcut

	private var __cancelDefault:Bool = false;

	public function new(x:Float = 0, y:Float = 0) {
		super();
	}

	var parentDisabler:FunkinParentDisabler;
	var canOpen:Bool = true;

	override function create()
	{
		super.create();

		#if !mobile
		if (menuItems.contains("Exit to charter") && !PlayState.chartingMode)
			menuItems.remove("Exit to charter");
		#end

		add(parentDisabler = new FunkinParentDisabler());

		pauseScript = Script.create(Paths.script(script));
		pauseScript.setParent(this);
		pauseScript.load();

		var event = EventManager.get(PauseCreationEvent).recycle('breakfast', menuItems);
		pauseScript.call('create', [event]);

		menuItems = event.options;


		pauseMusic = FlxG.sound.load(Paths.music(event.music), 0, true);
		pauseMusic.persist = false;
		pauseMusic.group = FlxG.sound.defaultMusicGroup;
		pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));

		if (__cancelDefault = event.cancelled) return;

		var bg:FlxSprite = new FlxSprite().makeSolid(FlxG.width + 100, FlxG.height + 100, FlxColor.BLACK);
		bg.updateHitbox();
		bg.alpha = 0;
		bg.screenCenter();
		bg.scrollFactor.set();
		add(bg);

		var levelInfo:FlxText = new FlxText(20, 15, 0, PlayState.SONG.meta.displayName, 32);
		var levelDifficulty:FlxText = new FlxText(20, 15, 0, PlayState.difficulty.toUpperCase(), 32);
		var deathCounter:FlxText = new FlxText(20, 15, 0, "Blue balled: " + PlayState.deathCounter, 32);
		var multiplayerText:FlxText = new FlxText(20, 15, 0, PlayState.opponentMode ? 'OPPONENT MODE' : (PlayState.coopMode ? 'CO-OP MODE' : ''), 32);

		for(k=>label in [levelInfo, levelDifficulty, deathCounter, multiplayerText]) {
			label.scrollFactor.set();
			label.setFormat(Paths.font('vcr.ttf'), 32);
			label.updateHitbox();
			label.alpha = 0;
			label.x = FlxG.width - (label.width + 20);
			label.y = 15 + (32 * k);
			FlxTween.tween(label, {alpha: 1, y: label.y + 5}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.3 * (k+1)});
			add(label);
		}

		FlxTween.tween(bg, {alpha: 0.6}, 0.4, {ease: FlxEase.quartInOut});

		grpMenuShit = new FlxTypedGroup<Alphabet>();
		add(grpMenuShit);

		for (i in 0...menuItems.length)
		{
			var songText:Alphabet = new Alphabet(0, (70 * i) + 30, menuItems[i], true, false);
			songText.isMenuItem = true;
			songText.targetY = i;
			grpMenuShit.add(songText);
		}

		changeSelection();

		camera = new FlxCamera();
		camera.bgColor = 0;
		FlxG.cameras.add(camera, false);

		pauseScript.call("postCreate");

		PlayState.instance.updateDiscordPresence();

		addVirtualPad(UP_DOWN, A_B);
		addVirtualPadCamera();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		pauseScript.call("update", [elapsed]);

		if (__cancelDefault) return;

		var upP = controls.UP_P;
		var downP = controls.DOWN_P;
		var accepted = controls.ACCEPT;

		if (upP)
			changeSelection(-1);
		if (downP)
			changeSelection(1);
		if (accepted)
			selectOption();
	}

	public function selectOption() {
		var event = EventManager.get(NameEvent).recycle(menuItems[curSelected]);
		pauseScript.call("onSelectOption", [event]);

		if (event.cancelled) return;

		var daSelected:String = event.name;

		switch (daSelected)
		{
			case "Resume":
				close();
			case "Restart Song":
				parentDisabler.reset();
				PlayState.instance.registerSmoothTransition();
				FlxG.resetState();
			case "Change Controls":
				persistentDraw = false;
				var daSubstate:Dynamic = new #if mobile mobile.substates.MobileControlSelectSubState(() -> {
					FlxG.state.persistentUpdate = true;
					camVPad.visible = true;
					new FlxTimer().start(0.2, (tmr:FlxTimer) -> canOpen = true);
				}, () -> {
					FlxG.state.persistentUpdate = false;
					camVPad.visible = false;
					canOpen = false;
				}) #else KeybindsOptions() #end;
				if(canOpen)
					openSubState(daSubstate);
			// case "Chart Editor":
			case "Change Options":
				FlxG.switchState(new OptionsMenu());
			case "Exit to charter":
				FlxG.switchState(new funkin.editors.charter.Charter(PlayState.SONG.meta.name, PlayState.difficulty, false));
			case "Exit to menu":
				if (PlayState.chartingMode && Charter.undos.unsaved)
					PlayState.instance.saveWarn(false);
				else {
					PlayState.resetSongInfos();
					if (Charter.instance != null) Charter.instance.__clearStatics();
					
					CoolUtil.playMenuSong();
					FlxG.switchState(PlayState.isStoryMode ? new StoryMenuState() : new FreeplayState());
				}

		}
	}
	override function destroy()
	{
		if(FlxG.cameras.list.contains(camera))
			FlxG.cameras.remove(camera, true);
		pauseScript.call("destroy");
		pauseScript.destroy();

		if (pauseMusic != null)
			@:privateAccess {
				FlxG.sound.destroySound(pauseMusic);
			}

		super.destroy();
	}

	function changeSelection(change:Int = 0):Void
	{
		var event = EventManager.get(MenuChangeEvent).recycle(curSelected, FlxMath.wrap(curSelected + change, 0, menuItems.length-1), change, change != 0);
		pauseScript.call("onChangeItem", [event]);
		if (event.cancelled) return;

		curSelected = event.value;

		for (i=>item in grpMenuShit.members)
		{
			item.targetY = i - curSelected;

			if (item.targetY == 0)
				item.alpha = 1;
			else
				item.alpha = 0.6;
		}
	}
}
