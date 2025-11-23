package objects;

import backend.animation.PsychAnimationController;
import backend.Song;
import backend.Paths;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxSort;
import flixel.util.FlxDestroyUtil;

#if flxanimate
import flxanimate.FlxAnimate;
#end

import haxe.Json;
import haxe.io.Bytes;
import haxe.zip.Reader;

import sys.FileSystem;
import sys.io.File;

using StringTools;

typedef CharacterFile = {
    var animations:Array<AnimArray>;
    var image:String;
    var scale:Float;
    var sing_duration:Float;
    var healthicon:String;

    var position:Array<Float>;
    var camera_position:Array<Float>;

    var flip_x:Bool;
    var no_antialiasing:Bool;
    var healthbar_colors:Array<Int>;
    var vocals_file:String;
    @:optional var _editor_isPlayer:Null<Bool>;
}

typedef AnimArray = {
    var anim:String;
    var name:String;
    var fps:Int;
    var loop:Bool;
    var indices:Array<Int>;
    var offsets:Array<Int>;
}

class Character extends FlxSprite
{
    /**
     * If a character JSON is missing, the system falls back to this.
     */
    public static final DEFAULT_CHARACTER:String = 'bf';

    public var animOffsets:Map<String, Array<Dynamic>>;
    public var debugMode:Bool = false;
    public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

    public var isPlayer:Bool = false;
    public var curCharacter:String = DEFAULT_CHARACTER;

    public var holdTimer:Float = 0;
    public var heyTimer:Float = 0;
    public var specialAnim:Bool = false;
    public var animationNotes:Array<Dynamic> = [];
    public var stunned:Bool = false;
    public var singDuration:Float = 4;
    public var idleSuffix:String = '';
    public var danceIdle:Bool = false;
    public var skipDance:Bool = false;

    public var healthIcon:String = 'face';
    public var animationsArray:Array<AnimArray> = [];

    public var positionArray:Array<Float> = [0, 0];
    public var cameraPosition:Array<Float> = [0, 0];
    public var healthColorArray:Array<Int> = [255, 0, 0];

    public var missingCharacter:Bool = false;
    public var missingText:FlxText;
    public var hasMissAnimations:Bool = false;
    public var vocalsFile:String = '';

    // Used by Character Editor
    public var imageFile:String = '';
    public var jsonScale:Float = 1;
    public var noAntialiasing:Bool = false;
    public var originalFlipX:Bool = false;
    public var editorIsPlayer:Null<Bool> = null;

    // NEW: ZIP support
    public var isAnimateZip(default, null):Bool = false;
    public var zipExtractPath:String = "";        // Path where ZIP extracted its atlas
    public var zipLoadedAnimJson:String = "";     // Path to Animation.json after unzip
    public var zipLoadedAtlasJson:String = "";    // Path to spritemap1.json
    public var zipLoadedAtlasPNG:String = "";     // Path to spritemap1.png

    #if flxanimate
    public var atlas:FlxAnimate;
    #end

    public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false)
    {
        super(x, y);

        animation = new PsychAnimationController(this);

        animOffsets = new Map<String, Array<Dynamic>>();
        this.isPlayer = isPlayer;
        changeCharacter(character);

        switch(curCharacter)
        {
            case 'pico-speaker':
                skipDance = true;
                loadMappedAnims();
                playAnim("shoot1");
            case 'pico-blazin', 'darnell-blazin':
                skipDance = true;
        }
    }
    public function changeCharacter(character:String)
    {
        animationsArray = [];
        animOffsets = [];
        curCharacter = character;

        var rawJSONPath:String = 'characters/$character.json';
        var charJsonPath:String = Paths.getPath(rawJSONPath, TEXT);

        var charZipPath:String = Paths.getPath('characters/$character.zip', BINARY);

        #if sys
        var hasZip:Bool = FileSystem.exists(charZipPath);
        #else
        var hasZip:Bool = false;
        #end

        var jsonData:Dynamic = null;

        if (hasZip)
        {
            try
            {
                loadZipCharacter(charZipPath);
                jsonData = Json.parse(File.getContent(zipLoadedAnimJson));
            }
            catch(e)
            {
                trace('ZIP load failed, falling back to normal JSON for $character: $e');
            }
        }

        // If ZIP load failed or ZIP not found → load normal JSON
        if (jsonData == null)
        {
            #if MODS_ALLOWED
            if (!FileSystem.exists(charJsonPath))
            #else
            if (!Assets.exists(charJsonPath))
            #end
            {
                charJsonPath = Paths.getSharedPath('characters/' + DEFAULT_CHARACTER + '.json');
                missingCharacter = true;
                missingText = new FlxText(0, 0, 300, 'ERROR:\n$character.json', 16);
                missingText.alignment = CENTER;
            }

            try
            {
                #if MODS_ALLOWED
                jsonData = Json.parse(File.getContent(charJsonPath));
                #else
                jsonData = Json.parse(Assets.getText(charJsonPath));
                #end
            }
            catch(e)
            {
                trace('Error loading character file "$character": $e');
            }
        }

        loadCharacterFile(jsonData);

        skipDance = false;
        hasMissAnimations = hasAnimation('singLEFTmiss') ||
                            hasAnimation('singDOWNmiss') ||
                            hasAnimation('singUPmiss') ||
                            hasAnimation('singRIGHTmiss');
        recalculateDanceIdle();
        dance();
    }

    #if sys
    function loadZipCharacter(zipPath:String)
    {
        isAnimateZip = false;
        zipExtractPath = Paths.mods('unzipped_' + curCharacter);

        if (!FileSystem.exists(zipExtractPath))
            FileSystem.createDirectory(zipExtractPath);

        var bytes:Bytes = File.getBytes(zipPath);
        var entries = Reader.readZip(bytes);

        for (entry in entries)
        {
            var fileName:String = entry.fileName;

            if (fileName.endsWith("/")) continue;

            var outPath:String = zipExtractPath + "/" + fileName;
            var dir = haxe.io.Path.directory(outPath);

            if (!FileSystem.exists(dir))
                FileSystem.createDirectory(dir);

            var data = entry.data;
            var out = File.write(outPath, true);
            out.write(data);
            out.close();

            if (fileName.toLowerCase() == "data.json")
                zipLoadedAnimJson = outPath;
            else if (fileName.toLowerCase() == "library.json")
                zipLoadedAtlasJson = outPath;
            else if (fileName.toLowerCase().endsWith(".png"))
                zipLoadedAtlasPNG = outPath;
        }

        if (zipLoadedAnimJson != "" && zipLoadedAtlasJson != "" && zipLoadedAtlasPNG != "")
        {
            isAnimateZip = true;
            trace("ZIP character loaded: " + curCharacter);
        }
        else
        {
            trace("ZIP load incomplete — missing files");
        }
    }
    #end

    public function loadCharacterFile(json:Dynamic)
    {
        isAnimateAtlas = false;

        // -------- ZIP ATLAS CHECK --------
        #if sys
        if (isAnimateZip)
        {
            try
            {
                atlas = new FlxAnimate();
                atlas.showPivot = false;

                // Load PNG + library.json + data.json
                var lib = Json.parse(File.getContent(zipLoadedAtlasJson));
                var dat = Json.parse(File.getContent(zipLoadedAnimJson));
                var pngBytes = File.getBytes(zipLoadedAtlasPNG);

                var bmp = BitmapData.fromBytes(pngBytes);

                atlas.loadFromData(dat, lib, bmp);
                isAnimateAtlas = true;

                trace("Loaded ZIP Animate character: " + curCharacter);
            }
            catch (e)
            {
                trace("FAILED to load ZIP atlas: " + e);
                isAnimateZip = false;
            }
        }
        #end
        // ---------------------------------

        // If ZIP didn't trigger Animate mode — check for normal Animate.json
        #if flxanimate
        if (!isAnimateAtlas)
        {
            var animToFind:String = Paths.getPath('images/' + json.image + '/Animation.json', TEXT);
            if (#if MODS_ALLOWED FileSystem.exists(animToFind) || #end Assets.exists(animToFind))
                isAnimateAtlas = true;
        }
        #end

        scale.set(1, 1);
        updateHitbox();

        //
        // LOAD GRAPHICS (MULTIATLAS or ANIMATE)
        //
        if (!isAnimateAtlas)
        {
            // Standard spritesheet / multi atlas
            frames = Paths.getMultiAtlas(json.image.split(','));
        }
        #if flxanimate
        else if (!isAnimateZip)
        {
            // Normal Animate atlas folder
            atlas = new FlxAnimate();
            atlas.showPivot = false;
            try
            {
                Paths.loadAnimateAtlas(atlas, json.image);
            }
            catch(e:haxe.Exception)
            {
                FlxG.log.warn('Could not load atlas ${json.image}: $e');
                trace(e.stack);
            }
        }
        #end

        //
        // BASIC CHARACTER DATA
        //
        imageFile = json.image;
        jsonScale = json.scale;

        if (json.scale != 1)
        {
            scale.set(jsonScale, jsonScale);
            updateHitbox();
        }

        positionArray = json.position;
        cameraPosition = json.camera_position;

        healthIcon = json.healthicon;
        singDuration = json.sing_duration;

        flipX = (json.flip_x != isPlayer);
        healthColorArray = (json.healthbar_colors != null && json.healthbar_colors.length > 2)
            ? json.healthbar_colors : [161, 161, 161];

        vocalsFile = json.vocals_file != null ? json.vocals_file : '';
        originalFlipX = (json.flip_x == true);
        editorIsPlayer = json._editor_isPlayer;

        noAntialiasing = (json.no_antialiasing == true);
        antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

        //
        // LOAD ANIMATIONS
        //
        animationsArray = json.animations;

        if (animationsArray != null && animationsArray.length > 0)
        {
            for (anim in animationsArray)
            {
                var animAnim:String = '' + anim.anim;
                var animName:String = '' + anim.name;
                var animFps:Int = anim.fps;
                var animLoop:Bool = !!anim.loop;
                var animIndices:Array<Int> = anim.indices;

                if (!isAnimateAtlas)
                {
                    if (animIndices != null && animIndices.length > 0)
                        animation.addByIndices(animAnim, animName, animIndices, "", animFps, animLoop);
                    else
                        animation.addByPrefix(animAnim, animName, animFps, animLoop);
                }
                #if flxanimate
                else
                {
                    if (animIndices != null && animIndices.length > 0)
                        atlas.anim.addBySymbolIndices(animAnim, animName, animIndices, animFps, animLoop);
                    else
                        atlas.anim.addBySymbol(animAnim, animName, animFps, animLoop);
                }
                #end

                if (anim.offsets != null && anim.offsets.length > 1)
                    addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
                else
                    addOffset(anim.anim, 0, 0);
            }
        }

        #if flxanimate
        if (isAnimateAtlas) copyAtlasValues();
        #end
    }

    override function update(elapsed:Float)
    {
        // ZIP & Animate update
        if (isAnimateAtlas)
        {
            atlas.update(elapsed);
        }

        if (debugMode ||
            (!isAnimateAtlas && animation.curAnim == null) ||
            (isAnimateAtlas && (atlas.anim.curInstance == null || atlas.anim.curSymbol == null)))
        {
            super.update(elapsed);
            return;
        }

        //
        // HEY ANIMATION LOGIC
        //
        if (heyTimer > 0)
        {
            var rate:Float = (PlayState.instance != null ? PlayState.instance.playbackRate : 1.0);
            heyTimer -= elapsed * rate;

            if (heyTimer <= 0)
            {
                var anim:String = getAnimationName();

                if (specialAnim && (anim == 'hey' || anim == 'cheer'))
                {
                    specialAnim = false;
                    dance();
                }

                heyTimer = 0;
            }
        }
        else if (specialAnim && isAnimationFinished())
        {
            specialAnim = false;
            dance();
        }
        else if (getAnimationName().endsWith('miss') && isAnimationFinished())
        {
            dance();
            finishAnimation();
        }

        //
        // SPECIAL CASE: PICO SPEAKER
        //
        switch(curCharacter)
        {
            case 'pico-speaker':
                if (animationNotes.length > 0 && Conductor.songPosition > animationNotes[0][0])
                {
                    var noteData:Int = 1;
                    if (animationNotes[0][1] > 2) noteData = 3;

                    noteData += FlxG.random.int(0, 1);
                    playAnim('shoot' + noteData, true);
                    animationNotes.shift();
                }

                if (isAnimationFinished() && !isAnimateAtlas)
                    playAnim(getAnimationName(), false, false, animation.curAnim.frames.length - 3);
        }

        //
        // HOLD TIMER
        //
        if (getAnimationName().startsWith('sing'))
            holdTimer += elapsed;
        else if (isPlayer)
            holdTimer = 0;

        if (!isPlayer &&
            holdTimer >= Conductor.stepCrochet * (0.0011
                #if FLX_PITCH / (FlxG.sound.music != null ? FlxG.sound.music.pitch : 1) #end)
                * singDuration)
        {
            dance();
            holdTimer = 0;
        }

        //
        // LOOPED ANIMATIONS
        //
        var name:String = getAnimationName();
        if (isAnimationFinished() && hasAnimation('$name-loop'))
            playAnim('$name-loop');

        super.update(elapsed);
    }

    inline public function isAnimationNull():Bool
    {
        return !isAnimateAtlas
            ? (animation.curAnim == null)
            : (atlas.anim.curInstance == null || atlas.anim.curSymbol == null);
    }

    var _lastPlayedAnimation:String;
    inline public function getAnimationName():String
    {
        return _lastPlayedAnimation;
    }

    public function isAnimationFinished():Bool
    {
        if (isAnimationNull()) return false;
        return !isAnimateAtlas ? animation.curAnim.finished : atlas.anim.finished;
    }

    public function finishAnimation():Void
    {
        if (isAnimationNull()) return;

        if (!isAnimateAtlas)
            animation.curAnim.finish();
        else
            atlas.anim.curFrame = atlas.anim.length - 1;
    }

    public function hasAnimation(anim:String):Bool
    {
        return animOffsets.exists(anim);
    }

    public var animPaused(get, set):Bool;

    private function get_animPaused():Bool
    {
        if (isAnimationNull()) return false;
        return !isAnimateAtlas ? animation.curAnim.paused : atlas.anim.isPlaying;
    }

    private function set_animPaused(value:Bool):Bool
    {
        if (isAnimationNull()) return value;

        if (!isAnimateAtlas)
            animation.curAnim.paused = value;
        else
        {
            if (value) atlas.pauseAnimation();
            else atlas.resumeAnimation();
        }

        return value;
    }

    public var danced:Bool = false;

    public function dance()
    {
        if (!debugMode && !skipDance && !specialAnim)
        {
            if (danceIdle)
            {
                danced = !danced;

                if (danced)
                    playAnim('danceRight' + idleSuffix);
                else
                    playAnim('danceLeft' + idleSuffix);
            }
            else if (hasAnimation('idle' + idleSuffix))
                playAnim('idle' + idleSuffix);
        }
    }

    public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void
    {
        specialAnim = false;

        if (!isAnimateAtlas)
        {
            animation.play(AnimName, Force, Reversed, Frame);
        }
        else
        {
            atlas.anim.play(AnimName, Force, Reversed, Frame);
            atlas.update(0);
        }

        _lastPlayedAnimation = AnimName;

        if (hasAnimation(AnimName))
        {
            var daOffset = animOffsets.get(AnimName);
            offset.set(daOffset[0], daOffset[1]);
        }

        //
        // GIRLFRIEND SPECIAL DANCE LOGIC
        //
        if (curCharacter.startsWith('gf-') || curCharacter == 'gf')
        {
            if (AnimName == 'singLEFT')
                danced = true;
            else if (AnimName == 'singRIGHT')
                danced = false;

            if (AnimName == 'singUP' || AnimName == 'singDOWN')
                danced = !danced;
        }
    }

    public function recalculateDanceIdle()
    {
        var lastDanceIdle:Bool = danceIdle;

        danceIdle = (hasAnimation('danceLeft' + idleSuffix) &&
                     hasAnimation('danceRight' + idleSuffix));

        if (settingCharacterUp)
        {
            danceEveryNumBeats = (danceIdle ? 1 : 2);
        }
        else if (lastDanceIdle != danceIdle)
        {
            var calc:Float = danceEveryNumBeats;

            if (danceIdle)
                calc /= 2;
            else
                calc *= 2;

            danceEveryNumBeats = Math.round(Math.max(calc, 1));
        }

        settingCharacterUp = false;
    }

    //
    // DRAWING FOR PNG → AND → ZIP & ANIMATE
    //
    #if flxanimate
    public override function draw()
    {
        var lastAlpha:Float = alpha;
        var lastColor:FlxColor = color;

        if (missingCharacter)
        {
            alpha *= 0.6;
            color = FlxColor.BLACK;
        }

        if (isAnimateAtlas)
        {
            if (atlas.anim.curInstance != null)
            {
                copyAtlasValues();
                atlas.draw();

                alpha = lastAlpha;
                color = lastColor;

                if (missingCharacter && visible)
                {
                    missingText.x = getMidpoint().x - 150;
                    missingText.y = getMidpoint().y - 10;
                    missingText.draw();
                }
            }
            return;
        }

        // Default drawing (PNG / MultiAtlas)
        super.draw();

        if (missingCharacter && visible)
        {
            alpha = lastAlpha;
            color = lastColor;

            missingText.x = getMidpoint().x - 150;
            missingText.y = getMidpoint().y - 10;
            missingText.draw();
        }
    }

    public function copyAtlasValues()
    {
        @:privateAccess
        {
            atlas.cameras = cameras;
            atlas.scrollFactor = scrollFactor;
            atlas.scale = scale;
            atlas.offset = offset;
            atlas.origin = origin;
            atlas.x = x;
            atlas.y = y;
            atlas.angle = angle;
            atlas.alpha = alpha;
            atlas.visible = visible;
            atlas.flipX = flipX;
            atlas.flipY = flipY;
            atlas.shader = shader;
            atlas.antialiasing = antialiasing;
            atlas.colorTransform = colorTransform;
            atlas.color = color;
        }
    }
    #end

