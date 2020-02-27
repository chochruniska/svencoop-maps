// Afraid of Monsters: Director's Cut Script
// Weapon Script: Revolver
// Author: Zorbos

const float REVOLVER_MOD_DAMAGE = 120.0;
const float REVOLVER_MOD_FIRERATE = 0.75;

const float REVOLVER_MOD_DAMAGE_SURVIVAL = 90.0; // Reduce damage by 25% on Survival

const int REVOLVER_DEFAULT_AMMO = 6;
const int REVOLVER_MAX_CARRY 	= 12;
const int REVOLVER_MAX_CLIP 	= 6;
const int REVOLVER_WEIGHT 		= 5;

enum revolver_e
{
	REVOLVER_IDLE1 = 0,
	REVOLVER_FIDGET,
	REVOLVER_FIRE1,
	REVOLVER_RELOAD,
	REVOLVER_HOLSTER,
	REVOLVER_DRAW,
	REVOLVER_IDLE2,
	REVOLVER_IDLE3
};

class weapon_dcrevolver : ScriptBasePlayerWeaponEntity
{
	private CBasePlayer@ m_pPlayer = null;
	private CScheduledFunction@ m_pPostDropItemSched = null;
	private bool bSurvivalEnabled = g_EngineFuncs.CVarGetFloat("mp_survival_starton") == 1 && g_EngineFuncs.CVarGetFloat("mp_survival_supported") == 1;
	
	int m_iShell;
	bool bIsFiring = false;

	void Spawn()
	{
		Precache();
		g_EntityFuncs.SetModel( self, "models/AoMDC/weapons/revolver/w_dcrevolver.mdl" );
		
		if(self.pev.targetname == "weapon_give")
			self.pev.spawnflags = 1024; // 1024 = Never respawn
		else if(self.pev.targetname == "weapon_dropped" || self.pev.targetname == "weapon_spawn")
			self.pev.spawnflags = 1280; // 1280 = USE Only + Never respawn
		
		if(self.pev.targetname == "weapon_dropped")
			self.m_iDefaultAmmo = self.m_iClip;
		else
			self.m_iDefaultAmmo = REVOLVER_DEFAULT_AMMO;

		self.FallInit();// get ready to fall
		
		// Makes it slightly easier to pickup the gun
		g_EntityFuncs.SetSize(self.pev, Vector( -4, -4, -1 ), Vector( 4, 4, 1 ));
	}

	void Precache()
	{
		self.PrecacheCustomModels();
		g_Game.PrecacheModel( "models/AoMDC/weapons/revolver/v_dcrevolver.mdl" );
		g_Game.PrecacheModel( "models/AoMDC/weapons/revolver/w_dcrevolver.mdl" );
		g_Game.PrecacheModel( "models/AoMDC/weapons/revolver/p_dcrevolver.mdl" );

		m_iShell = g_Game.PrecacheModel( "models/shell.mdl" ); // brass casing

		g_SoundSystem.PrecacheSound( "AoMDC/weapons/revolver/revolver_draw.wav" ); // draw sound
		g_SoundSystem.PrecacheSound( "AoMDC/weapons/revolver/revolver_reload.wav" ); // reloading sound
		g_SoundSystem.PrecacheSound( "AoMDC/weapons/revolver/revolver_fire.wav" ); // firing sound
	}

	bool AddToPlayer( CBasePlayer@ pPlayer )
	{
		if( !BaseClass.AddToPlayer( pPlayer ) )
			return false;
		
		// Hack: Recreate the weapon at this exact location to get around the +USE functionality
		// only working on the first pickup whilst still preserving cross-map inventory
		if(self.pev.targetname == "weapon_spawn")
		{
			string pOrigin = "" + self.pev.origin.x + " " +
								  self.pev.origin.y + " " +
								  self.pev.origin.z;
			string pAngles = "" + self.pev.angles.x + " " +
								  self.pev.angles.y + " " +
								  self.pev.angles.z;
			dictionary@ pValues = {{"origin", pOrigin}, {"angles", pAngles},{"spawnflags", "1024"}, {"targetname", "weapon_spawn"}};
			CBasePlayerWeapon@ pNew = cast<CBasePlayerWeapon>(g_EntityFuncs.CreateEntity(self.GetClassname(), @pValues, true));
		}
		
		@m_pPlayer = pPlayer;
		self.pev.targetname = ""; // Reset the targetname as this weapon is no longer "dropped"
		self.pev.noise3 = ""; // Reset the owner
		
		int m_iDuplicateClip = DeleteNearbyDuplicatesByOwner();
		
		if(m_iDuplicateClip >= 0)
			self.m_iClip = m_iDuplicateClip;
		
		// Can only have one weapon of this category at a time
		CBasePlayerItem@ pItem = pPlayer.HasNamedPlayerItem("weapon_dcdeagle");
		
		if(pItem !is null) // Player has a weapon in this category already
		{
			m_pPlayer.RemovePlayerItem(pItem); // Remove the existing weapon first
			ThrowWeapon(cast<CBasePlayerWeapon@>(pItem), true); // .. then spawn a new one
		}
			
		NetworkMessage message( MSG_ONE, NetworkMessages::WeapPickup, pPlayer.edict() );
			message.WriteLong( self.m_iId );
		message.End();
		
		m_pPlayer.SwitchWeapon(self);

		return true;
	}

	// Finds nearby dropped weapons that this player owns and removes them
	// Prevents spam by collecting the weapon over and over.
	int DeleteNearbyDuplicatesByOwner()
	{
		int m_iDuplicateClip;
		string m_iszOwnerId = g_EngineFuncs.GetPlayerAuthId(m_pPlayer.edict());
		CBaseEntity@ pStartEntity = null;
		
		 // Find nearby dropped weapons of the same classname as this one, owned by the same player who owns this one
		CBaseEntity@ pDuplicate = g_EntityFuncs.FindEntityInSphere(pStartEntity, self.pev.origin, 8192.0, m_iszOwnerId, "noise3");

		if(pDuplicate !is null && pDuplicate.GetClassname() == self.GetClassname())
		{
			CBasePlayerWeapon@ pWeapon = cast<CBasePlayerWeapon@>(pDuplicate);
			m_iDuplicateClip = pWeapon.m_iClip; // Save the current clip to import into the next weapon

			g_EntityFuncs.Remove(pDuplicate);
			
			return m_iDuplicateClip;
		}
		
		return -1; // No duplicate weapons found
	}
	
	bool GetItemInfo( ItemInfo& out info )
	{
		info.iMaxAmmo1 	= REVOLVER_MAX_CARRY;
		info.iMaxAmmo2 	= -1;
		info.iMaxClip 	= REVOLVER_MAX_CLIP;
		info.iSlot 		= 3;
		info.iPosition 	= 8;
		info.iFlags 	= 0;
		info.iWeight 	= REVOLVER_WEIGHT;

		return true;
	}

	void Holster( int skipLocal = 0 )
	{
		bIsFiring = false;
		m_pPlayer.m_flNextAttack = WeaponTimeBase() + 0.7f;
		BaseClass.Holster( skipLocal );
		
		if(m_pPostDropItemSched !is null)
			g_Scheduler.RemoveTimer(m_pPostDropItemSched);
		
		@m_pPostDropItemSched = g_Scheduler.SetTimeout(@this, "PostDropItem", 0.1);
	}
	
	// Creates a new weapon of the given type and "throws" it forward
	void ThrowWeapon(CBasePlayerWeapon@ pWeapon, bool bWasSwapped)
	{
		// Get player origin
		string plrOrigin = "" + m_pPlayer.pev.origin.x + " " +
							    m_pPlayer.pev.origin.y + " " +
							    (m_pPlayer.pev.origin.z + 20.0);
								
		// Get player angles
		string plrAngleCompY;
		
		// Different weapons need to be thrown out at different angles so that they face the player.
		if(pWeapon.GetClassname() == "weapon_dcdeagle")
			plrAngleCompY = m_pPlayer.pev.angles.y + 75.0;
		else
			plrAngleCompY = m_pPlayer.pev.angles.y - 110.0;
		
		string plrAngles = "" + m_pPlayer.pev.angles.x + " " +
							    plrAngleCompY + " " +
							    m_pPlayer.pev.angles.z;
								
		// Spawnflags 1280 = USE Only + Never respawn
		dictionary@ pValues = {{"origin", plrOrigin}, {"angles", plrAngles}, {"targetname", "weapon_dropped"}, {"noise3", ""}};
		
		if(bWasSwapped)
			pValues["noise3"] = g_EngineFuncs.GetPlayerAuthId(m_pPlayer.edict()); // The owner's STEAMID
		
		// Create the new item and "throw" it forward
		CBasePlayerWeapon@ pNew = cast<CBasePlayerWeapon@>(g_EntityFuncs.CreateEntity(pWeapon.GetClassname(), @pValues, true));
		
		if(pWeapon.GetClassname() == self.GetClassname()) // We're dropping THIS weapon
		{
			pNew.m_iClip = self.m_iClip; // Remember how many bullets are in the magazine
			m_pPlayer.m_rgAmmo(self.m_iPrimaryAmmoType, m_pPlayer.m_rgAmmo(self.m_iPrimaryAmmoType) * 2); // Stop ammo stacking
		}
		else // We're dropping a different weapon. Preserve it's current magazine state
			pNew.m_iClip = pWeapon.m_iClip;
			
		pNew.pev.velocity = g_Engine.v_forward * 200 + g_Engine.v_up * 125;
		
		m_pPlayer.SetItemPickupTimes(0);
	}
	
	// Handles the case in which this weapon is thrown VOLUNTARILY by the player or the player dies
	void PostDropItem()
	{
		CBaseEntity@ pWeaponbox = g_EntityFuncs.Instance(self.pev.owner); // The 'actual' thrown weapon
		
		if(pWeaponbox is null) // Failsafe(s)
			return;
		if(!pWeaponbox.pev.ClassNameIs("weaponbox"))
			return;
		
		// Remove the 'actual' dropped weapon..
		g_EntityFuncs.Remove(pWeaponbox);
		
		CBasePlayerWeapon@ pWeapon = self;
		
		// Spawn a new copy and "throw" it forward
		ThrowWeapon(pWeapon, false);
	}
	
	bool Deploy()
	{
		return self.DefaultDeploy( self.GetV_Model( "models/AoMDC/weapons/revolver/v_dcrevolver.mdl" ), self.GetP_Model( "models/AoMDC/weapons/revolver/p_dcrevolver.mdl" ), REVOLVER_DRAW, "python" );
	}

	float WeaponTimeBase()
	{
		return g_Engine.time; //g_WeaponFuncs.WeaponTimeBase();
	}

	void PrimaryAttack()
	{
		int m_iBulletDamage;
		
		if(bIsFiring)
			return;
			
		if(!bIsFiring)
			bIsFiring = true;
		// don't fire underwater
		if( m_pPlayer.pev.waterlevel == WATERLEVEL_HEAD )
		{
			self.m_flNextPrimaryAttack = WeaponTimeBase() + 0.35;
			return;
		}
	
		if (self.m_iClip == 0)
		{
			self.m_flNextPrimaryAttack = g_Engine.time + 0.55;
			return;
		}
		else if (self.m_iClip != 0)
		{
			self.SendWeaponAnim( REVOLVER_FIRE1, 0, 0 );
		}

		g_SoundSystem.EmitSoundDyn( m_pPlayer.edict(), CHAN_WEAPON, "AoMDC/weapons/revolver/revolver_fire.wav", Math.RandomFloat( 0.92, 1.0 ), ATTN_NORM, 0, 98 + Math.RandomLong( 0, 3 ) );

		m_pPlayer.m_iWeaponVolume = LOUD_GUN_VOLUME;
		m_pPlayer.m_iWeaponFlash = NORMAL_GUN_FLASH;

		--self.m_iClip;

		// player "shoot" animation
		m_pPlayer.SetAnimation( PLAYER_ATTACK1 );

		Vector vecSrc	 = m_pPlayer.GetGunPosition();
		Vector vecAiming = m_pPlayer.GetAutoaimVector( AUTOAIM_5DEGREES );

		if(bSurvivalEnabled)
			m_iBulletDamage = REVOLVER_MOD_DAMAGE_SURVIVAL;
		else
			m_iBulletDamage = REVOLVER_MOD_DAMAGE;
		
		m_pPlayer.FireBullets( 1, vecSrc, vecAiming, VECTOR_CONE_2DEGREES, 8192, BULLET_PLAYER_CUSTOMDAMAGE, 0, m_iBulletDamage );
		self.m_flNextPrimaryAttack = g_Engine.time + REVOLVER_MOD_FIRERATE;
		self.m_flTimeWeaponIdle = g_Engine.time + REVOLVER_MOD_FIRERATE;

		m_pPlayer.pev.punchangle.x = -4.0;
		
		TraceResult tr;
		float x, y;
		
		g_Utility.GetCircularGaussianSpread( x, y );
		
		Vector vecDir = vecAiming 
						+ x * VECTOR_CONE_3DEGREES.x * g_Engine.v_right 
						+ y * VECTOR_CONE_3DEGREES.y * g_Engine.v_up;

		Vector vecEnd	= vecSrc + vecDir * 4096;

		g_Utility.TraceLine( vecSrc, vecEnd, dont_ignore_monsters, m_pPlayer.edict(), tr );
		
		NetworkMessage mFlash(MSG_BROADCAST, NetworkMessages::SVC_TEMPENTITY);
			mFlash.WriteByte(TE_DLIGHT);
			mFlash.WriteCoord(m_pPlayer.GetGunPosition().x);
			mFlash.WriteCoord(m_pPlayer.GetGunPosition().y);
			mFlash.WriteCoord(m_pPlayer.GetGunPosition().z);
			mFlash.WriteByte(14); // Radius
			mFlash.WriteByte(255); // R
			mFlash.WriteByte(255); // G
			mFlash.WriteByte(204); // B
			mFlash.WriteByte(1); // Lifetime
			mFlash.WriteByte(1); // Decay
		mFlash.End();
		
		if( tr.flFraction < 1.0 )
		{
			if( tr.pHit !is null )
			{
				CBaseEntity@ pHit = g_EntityFuncs.Instance( tr.pHit );
				
				if( pHit is null || pHit.IsBSPModel() == true )
					g_WeaponFuncs.DecalGunshot( tr, BULLET_PLAYER_357 );
			}
		}
	}

	void WeaponIdle()
	{
		self.ResetEmptySound();

		if( self.m_flTimeWeaponIdle > WeaponTimeBase() )
			return;

		bIsFiring = false;

		self.m_flTimeWeaponIdle = g_Engine.time + REVOLVER_MOD_FIRERATE;
	}
	
	void Reload()
	{
		self.DefaultReload( 6, REVOLVER_RELOAD, 2.65, 0 );
		BaseClass.Reload();
	}
}

string GetDCRevolverName()
{
	return "weapon_dcrevolver";
}

void RegisterDCRevolver()
{
	g_CustomEntityFuncs.RegisterCustomEntity( "weapon_dcrevolver", GetDCRevolverName() );
	g_ItemRegistry.RegisterWeapon( GetDCRevolverName(), "AoMDC", "m40a1" );
}
