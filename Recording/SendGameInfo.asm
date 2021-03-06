################################################################################
# Address: 8016e74c
################################################################################
.include "Common/Common.s"
.include "Recording/Recording.s"
.include "Recording/SendInitialRNG.s"
.include "Recording/SendItemInfo.s"

################################################################################
# Routine: SendGameInfo
# ------------------------------------------------------------------------------
# Description: Gets the parameters that define the game such as stage,
# characters, settings, etc and write them out to Slippi device
################################################################################

.set REG_Buffer,30
.set REG_BufferOffset,29
.set REG_GeckoListSize,28
.set REG_GeckoCopyBuffer,27
.set REG_GeckoCopyPos,26

backup

# Check if VS Mode
  branchl r12,FN_IsVSMode
  cmpwi r3,0x0
  beq Injection_Exit

# initialize the write buffer that will be used throughout the game
# according to UnclePunch, all allocated memory gets free'd when the scene
# transitions. This means we don't need to worry about freeing this memory

#Create write buffer
  li  r3,FULL_FRAME_DATA_BUF_LENGTH
  branchl r12,HSD_MemAlloc
  mr  REG_Buffer,r3
  stw REG_Buffer,primaryDataBuffer(r13)
#Init current offset
  li  r3,0
  stw r3,bufferOffset(r13)

#------------- DETERMINE SIZE OF GECKO CODE SECTION -----------------
  load r3, GeckoCodeSectionStart # Gecko code list start
  li r4, 0 # No callback
  branchl r12, FN_ProcessGecko
  mr REG_GeckoListSize, r3

#------------- WRITE OUT COMMAND SIZES -------------
# start file sending and indicate the sizes of the output commands
  .set CommandSizesStart,0x0
  .set CommandSizesLength,MESSAGE_DESCRIPTIONS_PAYLOAD_LENGTH+1

  li r3, CMD_DESCRIPTIONS
  stb r3,CommandSizesStart+0x0(REG_Buffer)

# write out the payload size of the 0x35 command (includes this byte)
# we can write this in only a byte because I doubt it will ever be larger
# than 255. We write out the sizes of the other commands as half words for
# consistent parsing
  li r3, MESSAGE_DESCRIPTIONS_PAYLOAD_LENGTH
  stb r3,CommandSizesStart+0x1(REG_Buffer)

# game info command
  li r3, CMD_GAME_INFO
  stb r3,CommandSizesStart+0x2(REG_Buffer)
  li r3, GAME_INFO_PAYLOAD_LENGTH
  sth r3,CommandSizesStart+0x3(REG_Buffer)

# pre-frame update command
  li r3, CMD_PRE_FRAME
  stb r3,CommandSizesStart+0x5(REG_Buffer)
  li r3, GAME_PRE_FRAME_PAYLOAD_LENGTH
  sth r3,CommandSizesStart+0x6(REG_Buffer)

# post-frame update command
  li r3, CMD_POST_FRAME
  stb r3,CommandSizesStart+0x8(REG_Buffer)
  li r3, GAME_POST_FRAME_PAYLOAD_LENGTH
  sth r3,CommandSizesStart+0x9(REG_Buffer)

# game end command
  li r3, CMD_GAME_END
  stb r3,CommandSizesStart+0xB(REG_Buffer)
  li r3, GAME_END_PAYLOAD_LENGTH
  sth r3,CommandSizesStart+0xC(REG_Buffer)

# initial rng command
  li  r3,CMD_INITIAL_RNG
  stb r3,CommandSizesStart+0xE(REG_Buffer)
  li r3, GAME_INITIAL_RNG_PAYLOAD_LENGTH
  sth r3,CommandSizesStart+0xF(REG_Buffer)

# item data command
  li  r3,CMD_ITEM
  stb r3,CommandSizesStart+0x11(REG_Buffer)
  li r3, GAME_ITEM_INFO_PAYLOAD_LENGTH
  sth r3,CommandSizesStart+0x12(REG_Buffer)

# item data command
  li  r3,CMD_FRAME_BOOKEND
  stb r3,CommandSizesStart+0x14(REG_Buffer)
  li r3, GAME_FRAME_BOOKEND_PAYLOAD_LENGTH
  sth r3,CommandSizesStart+0x15(REG_Buffer)

# gecko code list command
  li r3, CMD_GECKO_LIST
  stb r3, CommandSizesStart+0x17(REG_Buffer)
  sth REG_GeckoListSize,CommandSizesStart+0x18(REG_Buffer)

# split message command
  li r3, CMD_SPLIT_MESSAGE
  stb r3, CommandSizesStart+0x1A(REG_Buffer)
  li r3, SPLIT_MESSAGE_PAYLOAD_LENGTH
  sth r3, CommandSizesStart+0x1B(REG_Buffer)

#------------- BEGIN GAME INFO COMMAND -------------
# game information message type
.set GameInfoCommandStart, (CommandSizesStart + CommandSizesLength)
.set GameInfoCommandLenth,0x5
  li r3, CMD_GAME_INFO
  stb r3,GameInfoCommandStart+0x0(REG_Buffer)

# build version number. Each byte is one digit
  load r3,CURRENT_VERSION
  stw r3,GameInfoCommandStart+0x1(REG_Buffer)

#------------- GAME INFO BLOCK -------------
# this iterates through the static game info block that is used to pull data
# from to initialize the game. it writes out the whole thing (0x138 long)
.set GameInfoBlockStart, (GameInfoCommandStart + GameInfoCommandLenth)
.set GameInfoBlockLength,0x138

  addi r3,REG_Buffer,GameInfoBlockStart
  mr  r4,r31
  li  r5,GameInfoBlockLength
  branchl r12,memcpy

#------------- ADJUST GAME INFO BLOCK FOR SHEIK -------------

.set REG_LoopCount,20
.set REG_PlayerDataStart,21

# Offsets
.set PlayerDataStart,96       #player data starts in match struct
.set PlayerDataLength,36      #length of each player's data
.set PlayerCharacter,0x0
.set PlayerStatus,0x1         #offset of players in-game status
.set Nametag,0xA              #offset of the nametag ID in the player's data

#Get game info in buffer
  addi  r3,REG_Buffer,GameInfoBlockStart
#Get to player data
  addi  REG_PlayerDataStart,r3,PlayerDataStart
#Init Loop Count
  li  REG_LoopCount,0
SEND_GAME_INFO_EDIT_SHEIK_LOOP:
#Get start of this players data
  mulli r22,REG_LoopCount,PlayerDataLength
  add r22,r22,REG_PlayerDataStart
#Check if this player is active
  lbz r3,PlayerStatus(r22)
  cmpwi r3,0x0
  bne SEND_GAME_INFO_EDIT_SHEIK_LOOP_INC
#Check if this player is zelda
  lbz r3,PlayerCharacter(r22)
  cmpwi r3,0x12
  bne SEND_GAME_INFO_EDIT_SHEIK_LOOP_INC
#Check if this player is holding A
  load r3,0x804c20bc
  mulli	r4, REG_LoopCount, 68
  add r3,r3,r4
  lwz r3,0x0(r3)
  rlwinm.	r0, r3, 0, 23, 23
  beq SEND_GAME_INFO_EDIT_SHEIK_LOOP_INC
#Change player to Sheik
  li  r3,0x13
  stb r3,PlayerCharacter(r22)

SEND_GAME_INFO_EDIT_SHEIK_LOOP_INC:
  addi  REG_LoopCount,REG_LoopCount,1
  cmpwi REG_LoopCount,4
  blt SEND_GAME_INFO_EDIT_SHEIK_LOOP

#------------- ENSURE COSTUMES ARE WITHIN BOUNDS -------------

.set REG_LoopCount,20
.set REG_PlayerDataStart,21

# Offsets
.set PlayerDataStart,96       #player data starts in match struct
.set PlayerDataLength,36      #length of each player's data
.set PlayerCharacter,0x0
.set PlayerCostume,0x3         #offset of players costume ID

#Get game info in buffer
  addi  r3,REG_Buffer,GameInfoBlockStart
#Get to player data
  addi  REG_PlayerDataStart,r3,PlayerDataStart
#Init Loop Count
  li  REG_LoopCount,0
ADJUST_COSTUME_NUMBER_LOOP:
#Get start of this players data
  mulli r22,REG_LoopCount,PlayerDataLength
  add r22,r22,REG_PlayerDataStart
#Check if this player is active
  lbz r3,PlayerStatus(r22)
  cmpwi r3,0x0
  bne ADJUST_COSTUME_NUMBER_LOOP_INC
#Get external character ID
  lbz r3,PlayerCharacter(r22)
  branchl r12, Character_GetMaxCostumeCount
#Get players costume ID
  lbz r4,PlayerCostume(r22)
  cmpw r4,r3
  ble ADJUST_COSTUME_NUMBER_LOOP_INC
#Change to first costume
  li  r3,0
  stb r3,PlayerCostume(r22)

ADJUST_COSTUME_NUMBER_LOOP_INC:
  addi  REG_LoopCount,REG_LoopCount,1
  cmpwi REG_LoopCount,4
  blt ADJUST_COSTUME_NUMBER_LOOP

#------------- OTHER INFO -------------
.set RNGSeedStart, (GameInfoBlockStart+ GameInfoBlockLength)
.set RNGSeedLength,0x4

# write out random seed
  lis r3, 0x804D
  lwz r3, 0x5F90(r3) #load random seed
  stw r3, RNGSeedStart+0x0(REG_Buffer)

#------------- SEND UCF Toggles ------------
.set UCFToggleStart, (RNGSeedStart+ RNGSeedLength)
.set UCFToggleLength,0x20

# write UCF toggle bytes
  subi r20,rtoc,ControllerFixOptions    #Get UCF toggles
  li  r21,0                 #Init loop
  addi r22,REG_Buffer,UCFToggleStart
UCF_LOOP:
  mulli r23,r21,8
  lbzx r3,r21,r20           #Get toggle value
  stwx r3,r22,r23
  addi r23,r23,4            #Next offset
  stwx r3,r22,r23           #send toggle value again for compatibility with old .slp files
  addi  r21,r21,1
  cmpwi r21,4
  blt UCF_LOOP

#------------- SEND NAMETAGS ------------
# Loop through players 1-4 and send their nametag data
# r31 contains the match struct fed into StartMelee. We'll
# be using this to find each player's nametag slot
.set NametagDataStart, (UCFToggleStart+ UCFToggleLength)
.set NametagDataLength,0x40

# Offsets
.set PlayerDataStart,96       #player data starts in match struct
.set PlayerDataLength,36      #length of each player's data
.set PlayerStatus,0x1         #offset of players in-game status
.set Nametag,0xA              #offset of the nametag ID in the player's data
# Constants
.set CharactersToCopy, 8 *2
# Registers
.set REG_LoopCount,20
.set REG_PlayerDataStart,21
.set REG_CurrentPlayerData,22

# Init loop
  li  REG_LoopCount,0                               #init loop count
  addi REG_PlayerDataStart,r31,PlayerDataStart     #player data start in match struct
  addi r23,REG_Buffer,NametagDataStart              #Start of nametag data in buffer
SEND_GAME_INFO_NAMETAG_LOOP:
#Get nametag data in buffer in r24
  mulli r24,REG_LoopCount,CharactersToCopy
  add r24,r24,r23
# Get players data
  mulli REG_CurrentPlayerData,REG_LoopCount,PlayerDataLength
  add REG_CurrentPlayerData,REG_CurrentPlayerData,REG_PlayerDataStart
# Check if player is in game && human
  lbz r3,PlayerStatus(REG_CurrentPlayerData)
  cmpwi r3,0x0
  bne SEND_GAME_INFO_NAMETAG_NO_TAG
# Check if player has a nametag
  lbz r3,Nametag(REG_CurrentPlayerData)
  cmpwi r3,0x78
  beq SEND_GAME_INFO_NAMETAG_NO_TAG
#Get nametag string
  branchl r12,Nametag_LoadSlotText
# Copy first 8 characters to nametag to buffer
  mr  r4,r3
  mr  r3,r24
  li  r5,CharactersToCopy
  branchl r12,memcpy
  b SEND_GAME_INFO_NAMETAG_INC_LOOP

SEND_GAME_INFO_NAMETAG_NO_TAG:
# Fill with zeroes
  mr r3,r24
  li r4,CharactersToCopy
  branchl r12,Zero_AreaLength

SEND_GAME_INFO_NAMETAG_INC_LOOP:
# Increment Loop
  addi REG_LoopCount,REG_LoopCount,1
  cmpwi REG_LoopCount,4
  blt SEND_GAME_INFO_NAMETAG_LOOP

#------------- SEND PAL Toggle ------------
.set PALToggleStart, (NametagDataStart+ NametagDataLength)
.set PALToggleLength,0x1

  lbz r3,PALToggle(rtoc)
  stb r3,PALToggleStart+0x0(REG_Buffer)

#------------- SEND Frozen Stadium Toggle ------------
.set FSToggleStart, (PALToggleStart+ PALToggleLength)
.set FSToggleLength,0x1

  lbz r3,FSToggle(rtoc)
  stb r3,FSToggleStart+0x0(REG_Buffer)

#------------- Transfer Buffer ------------
  mr  r3,REG_Buffer
  li  r4,MESSAGE_DESCRIPTIONS_PAYLOAD_LENGTH+1 + GAME_INFO_PAYLOAD_LENGTH+1
  li  r5,CONST_ExiWrite
  branchl r12,FN_EXITransferBuffer

#-------------- Transfer Gecko List ---------------
# Create copy buffer
  li r3, SPLIT_MESSAGE_BUF_LEN
  branchl r12, HSD_MemAlloc
  mr REG_GeckoCopyBuffer, r3

  li r3, CMD_SPLIT_MESSAGE
  stb r3, SPLIT_MESSAGE_OFST_COMMAND(REG_GeckoCopyBuffer)

  # Copy command
  li r3, CMD_GECKO_LIST
  stb r3, SPLIT_MESSAGE_OFST_INTERNAL_CMD(REG_GeckoCopyBuffer)

  # Initialize the data size, will be overwritten once last message is sent
  li r3, SPLIT_MESSAGE_INTERNAL_DATA_LEN
  sth r3, SPLIT_MESSAGE_OFST_SIZE(REG_GeckoCopyBuffer)

  # Initialize isComplete, will be overwritten once last message is sent
  li r3, 0
  stb r3, SPLIT_MESSAGE_OFST_IS_COMPLETE(REG_GeckoCopyBuffer)

  li REG_GeckoCopyPos, 0

CODE_LIST_LOOP_START:
  sub r3, REG_GeckoListSize, REG_GeckoCopyPos
  cmpwi r3, SPLIT_MESSAGE_INTERNAL_DATA_LEN
  bgt CODE_LIST_COPY_BLOCK

  # This is the last message, write the size
  sth r3, SPLIT_MESSAGE_OFST_SIZE(REG_GeckoCopyBuffer)

  # Indicate last message
  li r3, 1
  stb r3, SPLIT_MESSAGE_OFST_IS_COMPLETE(REG_GeckoCopyBuffer)

CODE_LIST_COPY_BLOCK:
  # Copy next gecko list section
  addi r3, REG_GeckoCopyBuffer, SPLIT_MESSAGE_OFST_DATA # destination
  load r4, GeckoCodeSectionStart
  add r4, r4, REG_GeckoCopyPos
  lhz r5, SPLIT_MESSAGE_OFST_SIZE(REG_GeckoCopyBuffer)
  branchl r12, memcpy

  # Transfer codes
  mr r3, REG_GeckoCopyBuffer
  li r4, SPLIT_MESSAGE_BUF_LEN
  li r5, CONST_ExiWrite
  branchl r12, FN_EXITransferBuffer

  addi REG_GeckoCopyPos, REG_GeckoCopyPos, SPLIT_MESSAGE_INTERNAL_DATA_LEN
  cmpw REG_GeckoCopyPos, REG_GeckoListSize
  blt CODE_LIST_LOOP_START

CODE_LIST_CLEANUP:
  # Free memory
  mr r3, REG_GeckoCopyBuffer
  branchl r12, HSD_Free

# run macro to create the SendInitialRNG process
  Macro_SendInitialRNG

# run macro to create SendProjectileInfo process
  Macro_SendItemInfo

Injection_Exit:
  restore
  lis	r3, 0x8017
