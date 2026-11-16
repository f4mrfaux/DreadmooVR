using UnrealBuildTool;

public class DreadmoorTarget : TargetRules
{
	public DreadmoorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.V5;
		IncludeOrderVersion = EngineIncludeOrderVersion.Unreal5_6;
		ExtraModuleNames.Add("Dreadmoor");
	}
}
