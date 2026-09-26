#[allow(unused)]
mod data {
    use crate::*;
pub const PIECE_STATES_FOR_HEIGHT_AND_PIECE: &'static [[&'static [PieceState]; 7]; 6] = &[
[
&[],
&[],
&[],
&[],
&[],
&[],
&[PieceState::IHorizontal0,],
],
[
&[PieceState::SHorizontal00,],
&[PieceState::ZHorizontal00,],
&[PieceState::JNorth00,PieceState::JSouth00,],
&[PieceState::LNorth00,PieceState::LSouth00,],
&[PieceState::TNorth00,PieceState::TSouth00,],
&[PieceState::O00,],
&[PieceState::IHorizontal0,PieceState::IHorizontal1,],
],
[
&[PieceState::SHorizontal00,PieceState::SHorizontal01,PieceState::SHorizontal10,PieceState::SVertical000,],
&[PieceState::ZHorizontal00,PieceState::ZHorizontal01,PieceState::ZHorizontal10,PieceState::ZVertical000,],
&[PieceState::JNorth00,PieceState::JNorth01,PieceState::JNorth10,PieceState::JSouth00,PieceState::JSouth01,PieceState::JSouth10,PieceState::JEast000,PieceState::JWest000,],
&[PieceState::LNorth00,PieceState::LNorth01,PieceState::LNorth10,PieceState::LSouth00,PieceState::LSouth01,PieceState::LSouth10,PieceState::LEast000,PieceState::LWest000,],
&[PieceState::TNorth00,PieceState::TNorth01,PieceState::TNorth10,PieceState::TSouth00,PieceState::TSouth01,PieceState::TSouth10,PieceState::TEast000,PieceState::TWest000,],
&[PieceState::O00,PieceState::O01,PieceState::O10,],
&[PieceState::IHorizontal0,PieceState::IHorizontal1,PieceState::IHorizontal2,],
],
[
&[PieceState::SHorizontal00,PieceState::SHorizontal01,PieceState::SHorizontal02,PieceState::SHorizontal10,PieceState::SHorizontal11,PieceState::SHorizontal20,PieceState::SVertical000,PieceState::SVertical001,PieceState::SVertical010,PieceState::SVertical100,],
&[PieceState::ZHorizontal00,PieceState::ZHorizontal01,PieceState::ZHorizontal02,PieceState::ZHorizontal10,PieceState::ZHorizontal11,PieceState::ZHorizontal20,PieceState::ZVertical000,PieceState::ZVertical001,PieceState::ZVertical010,PieceState::ZVertical100,],
&[PieceState::JNorth00,PieceState::JNorth01,PieceState::JNorth02,PieceState::JNorth10,PieceState::JNorth11,PieceState::JNorth20,PieceState::JSouth00,PieceState::JSouth01,PieceState::JSouth02,PieceState::JSouth10,PieceState::JSouth11,PieceState::JSouth20,PieceState::JEast000,PieceState::JEast001,PieceState::JEast010,PieceState::JEast100,PieceState::JWest000,PieceState::JWest001,PieceState::JWest010,PieceState::JWest100,],
&[PieceState::LNorth00,PieceState::LNorth01,PieceState::LNorth02,PieceState::LNorth10,PieceState::LNorth11,PieceState::LNorth20,PieceState::LSouth00,PieceState::LSouth01,PieceState::LSouth02,PieceState::LSouth10,PieceState::LSouth11,PieceState::LSouth20,PieceState::LEast000,PieceState::LEast001,PieceState::LEast010,PieceState::LEast100,PieceState::LWest000,PieceState::LWest001,PieceState::LWest010,PieceState::LWest100,],
&[PieceState::TNorth00,PieceState::TNorth01,PieceState::TNorth02,PieceState::TNorth10,PieceState::TNorth11,PieceState::TNorth20,PieceState::TSouth00,PieceState::TSouth01,PieceState::TSouth02,PieceState::TSouth10,PieceState::TSouth11,PieceState::TSouth20,PieceState::TEast000,PieceState::TEast001,PieceState::TEast010,PieceState::TEast100,PieceState::TWest000,PieceState::TWest001,PieceState::TWest010,PieceState::TWest100,],
&[PieceState::O00,PieceState::O01,PieceState::O02,PieceState::O10,PieceState::O11,PieceState::O20,],
&[PieceState::IHorizontal0,PieceState::IHorizontal1,PieceState::IHorizontal2,PieceState::IHorizontal3,PieceState::IVertical0000,],
],
[
&[PieceState::SHorizontal00,PieceState::SHorizontal01,PieceState::SHorizontal02,PieceState::SHorizontal03,PieceState::SHorizontal10,PieceState::SHorizontal11,PieceState::SHorizontal12,PieceState::SHorizontal20,PieceState::SHorizontal21,PieceState::SHorizontal30,PieceState::SVertical000,PieceState::SVertical001,PieceState::SVertical002,PieceState::SVertical010,PieceState::SVertical011,PieceState::SVertical020,PieceState::SVertical100,PieceState::SVertical101,PieceState::SVertical110,PieceState::SVertical200,],
&[PieceState::ZHorizontal00,PieceState::ZHorizontal01,PieceState::ZHorizontal02,PieceState::ZHorizontal03,PieceState::ZHorizontal10,PieceState::ZHorizontal11,PieceState::ZHorizontal12,PieceState::ZHorizontal20,PieceState::ZHorizontal21,PieceState::ZHorizontal30,PieceState::ZVertical000,PieceState::ZVertical001,PieceState::ZVertical002,PieceState::ZVertical010,PieceState::ZVertical011,PieceState::ZVertical020,PieceState::ZVertical100,PieceState::ZVertical101,PieceState::ZVertical110,PieceState::ZVertical200,],
&[PieceState::JNorth00,PieceState::JNorth01,PieceState::JNorth02,PieceState::JNorth03,PieceState::JNorth10,PieceState::JNorth11,PieceState::JNorth12,PieceState::JNorth20,PieceState::JNorth21,PieceState::JNorth30,PieceState::JSouth00,PieceState::JSouth01,PieceState::JSouth02,PieceState::JSouth03,PieceState::JSouth10,PieceState::JSouth11,PieceState::JSouth12,PieceState::JSouth20,PieceState::JSouth21,PieceState::JSouth30,PieceState::JEast000,PieceState::JEast001,PieceState::JEast002,PieceState::JEast010,PieceState::JEast011,PieceState::JEast020,PieceState::JEast100,PieceState::JEast101,PieceState::JEast110,PieceState::JEast200,PieceState::JWest000,PieceState::JWest001,PieceState::JWest002,PieceState::JWest010,PieceState::JWest011,PieceState::JWest020,PieceState::JWest100,PieceState::JWest101,PieceState::JWest110,PieceState::JWest200,],
&[PieceState::LNorth00,PieceState::LNorth01,PieceState::LNorth02,PieceState::LNorth03,PieceState::LNorth10,PieceState::LNorth11,PieceState::LNorth12,PieceState::LNorth20,PieceState::LNorth21,PieceState::LNorth30,PieceState::LSouth00,PieceState::LSouth01,PieceState::LSouth02,PieceState::LSouth03,PieceState::LSouth10,PieceState::LSouth11,PieceState::LSouth12,PieceState::LSouth20,PieceState::LSouth21,PieceState::LSouth30,PieceState::LEast000,PieceState::LEast001,PieceState::LEast002,PieceState::LEast010,PieceState::LEast011,PieceState::LEast020,PieceState::LEast100,PieceState::LEast101,PieceState::LEast110,PieceState::LEast200,PieceState::LWest000,PieceState::LWest001,PieceState::LWest002,PieceState::LWest010,PieceState::LWest011,PieceState::LWest020,PieceState::LWest100,PieceState::LWest101,PieceState::LWest110,PieceState::LWest200,],
&[PieceState::TNorth00,PieceState::TNorth01,PieceState::TNorth02,PieceState::TNorth03,PieceState::TNorth10,PieceState::TNorth11,PieceState::TNorth12,PieceState::TNorth20,PieceState::TNorth21,PieceState::TNorth30,PieceState::TSouth00,PieceState::TSouth01,PieceState::TSouth02,PieceState::TSouth03,PieceState::TSouth10,PieceState::TSouth11,PieceState::TSouth12,PieceState::TSouth20,PieceState::TSouth21,PieceState::TSouth30,PieceState::TEast000,PieceState::TEast001,PieceState::TEast002,PieceState::TEast010,PieceState::TEast011,PieceState::TEast020,PieceState::TEast100,PieceState::TEast101,PieceState::TEast110,PieceState::TEast200,PieceState::TWest000,PieceState::TWest001,PieceState::TWest002,PieceState::TWest010,PieceState::TWest011,PieceState::TWest020,PieceState::TWest100,PieceState::TWest101,PieceState::TWest110,PieceState::TWest200,],
&[PieceState::O00,PieceState::O01,PieceState::O02,PieceState::O03,PieceState::O10,PieceState::O11,PieceState::O12,PieceState::O20,PieceState::O21,PieceState::O30,],
&[PieceState::IHorizontal0,PieceState::IHorizontal1,PieceState::IHorizontal2,PieceState::IHorizontal3,PieceState::IHorizontal4,PieceState::IVertical0000,PieceState::IVertical0001,PieceState::IVertical0010,PieceState::IVertical0100,PieceState::IVertical1000,],
],
[
&[PieceState::SHorizontal00,PieceState::SHorizontal01,PieceState::SHorizontal02,PieceState::SHorizontal03,PieceState::SHorizontal04,PieceState::SHorizontal10,PieceState::SHorizontal11,PieceState::SHorizontal12,PieceState::SHorizontal13,PieceState::SHorizontal20,PieceState::SHorizontal21,PieceState::SHorizontal22,PieceState::SHorizontal30,PieceState::SHorizontal31,PieceState::SHorizontal40,PieceState::SVertical000,PieceState::SVertical001,PieceState::SVertical002,PieceState::SVertical003,PieceState::SVertical010,PieceState::SVertical011,PieceState::SVertical012,PieceState::SVertical020,PieceState::SVertical021,PieceState::SVertical030,PieceState::SVertical100,PieceState::SVertical101,PieceState::SVertical102,PieceState::SVertical110,PieceState::SVertical111,PieceState::SVertical120,PieceState::SVertical200,PieceState::SVertical201,PieceState::SVertical210,PieceState::SVertical300,],
&[PieceState::ZHorizontal00,PieceState::ZHorizontal01,PieceState::ZHorizontal02,PieceState::ZHorizontal03,PieceState::ZHorizontal04,PieceState::ZHorizontal10,PieceState::ZHorizontal11,PieceState::ZHorizontal12,PieceState::ZHorizontal13,PieceState::ZHorizontal20,PieceState::ZHorizontal21,PieceState::ZHorizontal22,PieceState::ZHorizontal30,PieceState::ZHorizontal31,PieceState::ZHorizontal40,PieceState::ZVertical000,PieceState::ZVertical001,PieceState::ZVertical002,PieceState::ZVertical003,PieceState::ZVertical010,PieceState::ZVertical011,PieceState::ZVertical012,PieceState::ZVertical020,PieceState::ZVertical021,PieceState::ZVertical030,PieceState::ZVertical100,PieceState::ZVertical101,PieceState::ZVertical102,PieceState::ZVertical110,PieceState::ZVertical111,PieceState::ZVertical120,PieceState::ZVertical200,PieceState::ZVertical201,PieceState::ZVertical210,PieceState::ZVertical300,],
&[PieceState::JNorth00,PieceState::JNorth01,PieceState::JNorth02,PieceState::JNorth03,PieceState::JNorth04,PieceState::JNorth10,PieceState::JNorth11,PieceState::JNorth12,PieceState::JNorth13,PieceState::JNorth20,PieceState::JNorth21,PieceState::JNorth22,PieceState::JNorth30,PieceState::JNorth31,PieceState::JNorth40,PieceState::JSouth00,PieceState::JSouth01,PieceState::JSouth02,PieceState::JSouth03,PieceState::JSouth04,PieceState::JSouth10,PieceState::JSouth11,PieceState::JSouth12,PieceState::JSouth13,PieceState::JSouth20,PieceState::JSouth21,PieceState::JSouth22,PieceState::JSouth30,PieceState::JSouth31,PieceState::JSouth40,PieceState::JEast000,PieceState::JEast001,PieceState::JEast002,PieceState::JEast003,PieceState::JEast010,PieceState::JEast011,PieceState::JEast012,PieceState::JEast020,PieceState::JEast021,PieceState::JEast030,PieceState::JEast100,PieceState::JEast101,PieceState::JEast102,PieceState::JEast110,PieceState::JEast111,PieceState::JEast120,PieceState::JEast200,PieceState::JEast201,PieceState::JEast210,PieceState::JEast300,PieceState::JWest000,PieceState::JWest001,PieceState::JWest002,PieceState::JWest003,PieceState::JWest010,PieceState::JWest011,PieceState::JWest012,PieceState::JWest020,PieceState::JWest021,PieceState::JWest030,PieceState::JWest100,PieceState::JWest101,PieceState::JWest102,PieceState::JWest110,PieceState::JWest111,PieceState::JWest120,PieceState::JWest200,PieceState::JWest201,PieceState::JWest210,PieceState::JWest300,],
&[PieceState::LNorth00,PieceState::LNorth01,PieceState::LNorth02,PieceState::LNorth03,PieceState::LNorth04,PieceState::LNorth10,PieceState::LNorth11,PieceState::LNorth12,PieceState::LNorth13,PieceState::LNorth20,PieceState::LNorth21,PieceState::LNorth22,PieceState::LNorth30,PieceState::LNorth31,PieceState::LNorth40,PieceState::LSouth00,PieceState::LSouth01,PieceState::LSouth02,PieceState::LSouth03,PieceState::LSouth04,PieceState::LSouth10,PieceState::LSouth11,PieceState::LSouth12,PieceState::LSouth13,PieceState::LSouth20,PieceState::LSouth21,PieceState::LSouth22,PieceState::LSouth30,PieceState::LSouth31,PieceState::LSouth40,PieceState::LEast000,PieceState::LEast001,PieceState::LEast002,PieceState::LEast003,PieceState::LEast010,PieceState::LEast011,PieceState::LEast012,PieceState::LEast020,PieceState::LEast021,PieceState::LEast030,PieceState::LEast100,PieceState::LEast101,PieceState::LEast102,PieceState::LEast110,PieceState::LEast111,PieceState::LEast120,PieceState::LEast200,PieceState::LEast201,PieceState::LEast210,PieceState::LEast300,PieceState::LWest000,PieceState::LWest001,PieceState::LWest002,PieceState::LWest003,PieceState::LWest010,PieceState::LWest011,PieceState::LWest012,PieceState::LWest020,PieceState::LWest021,PieceState::LWest030,PieceState::LWest100,PieceState::LWest101,PieceState::LWest102,PieceState::LWest110,PieceState::LWest111,PieceState::LWest120,PieceState::LWest200,PieceState::LWest201,PieceState::LWest210,PieceState::LWest300,],
&[PieceState::TNorth00,PieceState::TNorth01,PieceState::TNorth02,PieceState::TNorth03,PieceState::TNorth04,PieceState::TNorth10,PieceState::TNorth11,PieceState::TNorth12,PieceState::TNorth13,PieceState::TNorth20,PieceState::TNorth21,PieceState::TNorth22,PieceState::TNorth30,PieceState::TNorth31,PieceState::TNorth40,PieceState::TSouth00,PieceState::TSouth01,PieceState::TSouth02,PieceState::TSouth03,PieceState::TSouth04,PieceState::TSouth10,PieceState::TSouth11,PieceState::TSouth12,PieceState::TSouth13,PieceState::TSouth20,PieceState::TSouth21,PieceState::TSouth22,PieceState::TSouth30,PieceState::TSouth31,PieceState::TSouth40,PieceState::TEast000,PieceState::TEast001,PieceState::TEast002,PieceState::TEast003,PieceState::TEast010,PieceState::TEast011,PieceState::TEast012,PieceState::TEast020,PieceState::TEast021,PieceState::TEast030,PieceState::TEast100,PieceState::TEast101,PieceState::TEast102,PieceState::TEast110,PieceState::TEast111,PieceState::TEast120,PieceState::TEast200,PieceState::TEast201,PieceState::TEast210,PieceState::TEast300,PieceState::TWest000,PieceState::TWest001,PieceState::TWest002,PieceState::TWest003,PieceState::TWest010,PieceState::TWest011,PieceState::TWest012,PieceState::TWest020,PieceState::TWest021,PieceState::TWest030,PieceState::TWest100,PieceState::TWest101,PieceState::TWest102,PieceState::TWest110,PieceState::TWest111,PieceState::TWest120,PieceState::TWest200,PieceState::TWest201,PieceState::TWest210,PieceState::TWest300,],
&[PieceState::O00,PieceState::O01,PieceState::O02,PieceState::O03,PieceState::O04,PieceState::O10,PieceState::O11,PieceState::O12,PieceState::O13,PieceState::O20,PieceState::O21,PieceState::O22,PieceState::O30,PieceState::O31,PieceState::O40,],
&[PieceState::IHorizontal0,PieceState::IHorizontal1,PieceState::IHorizontal2,PieceState::IHorizontal3,PieceState::IHorizontal4,PieceState::IHorizontal5,PieceState::IVertical0000,PieceState::IVertical0001,PieceState::IVertical0002,PieceState::IVertical0010,PieceState::IVertical0011,PieceState::IVertical0020,PieceState::IVertical0100,PieceState::IVertical0101,PieceState::IVertical0110,PieceState::IVertical0200,PieceState::IVertical1000,PieceState::IVertical1001,PieceState::IVertical1010,PieceState::IVertical1100,PieceState::IVertical2000,],
],
];
#[derive(Copy, Clone, Debug, Eq, PartialEq, Hash)] pub enum PieceState {SHorizontal00,SHorizontal01,SHorizontal02,SHorizontal03,SHorizontal04,SHorizontal10,SHorizontal11,SHorizontal12,SHorizontal13,SHorizontal20,SHorizontal21,SHorizontal22,SHorizontal30,SHorizontal31,SHorizontal40,SVertical000,SVertical001,SVertical002,SVertical003,SVertical010,SVertical011,SVertical012,SVertical020,SVertical021,SVertical030,SVertical100,SVertical101,SVertical102,SVertical110,SVertical111,SVertical120,SVertical200,SVertical201,SVertical210,SVertical300,ZHorizontal00,ZHorizontal01,ZHorizontal02,ZHorizontal03,ZHorizontal04,ZHorizontal10,ZHorizontal11,ZHorizontal12,ZHorizontal13,ZHorizontal20,ZHorizontal21,ZHorizontal22,ZHorizontal30,ZHorizontal31,ZHorizontal40,ZVertical000,ZVertical001,ZVertical002,ZVertical003,ZVertical010,ZVertical011,ZVertical012,ZVertical020,ZVertical021,ZVertical030,ZVertical100,ZVertical101,ZVertical102,ZVertical110,ZVertical111,ZVertical120,ZVertical200,ZVertical201,ZVertical210,ZVertical300,IHorizontal0,IHorizontal1,IHorizontal2,IHorizontal3,IHorizontal4,IHorizontal5,IVertical0000,IVertical0001,IVertical0002,IVertical0010,IVertical0011,IVertical0020,IVertical0100,IVertical0101,IVertical0110,IVertical0200,IVertical1000,IVertical1001,IVertical1010,IVertical1100,IVertical2000,JNorth00,JNorth01,JNorth02,JNorth03,JNorth04,JNorth10,JNorth11,JNorth12,JNorth13,JNorth20,JNorth21,JNorth22,JNorth30,JNorth31,JNorth40,TNorth00,TNorth01,TNorth02,TNorth03,TNorth04,TNorth10,TNorth11,TNorth12,TNorth13,TNorth20,TNorth21,TNorth22,TNorth30,TNorth31,TNorth40,LNorth00,LNorth01,LNorth02,LNorth03,LNorth04,LNorth10,LNorth11,LNorth12,LNorth13,LNorth20,LNorth21,LNorth22,LNorth30,LNorth31,LNorth40,JSouth00,JSouth01,JSouth02,JSouth03,JSouth04,JSouth10,JSouth11,JSouth12,JSouth13,JSouth20,JSouth21,JSouth22,JSouth30,JSouth31,JSouth40,TSouth00,TSouth01,TSouth02,TSouth03,TSouth04,TSouth10,TSouth11,TSouth12,TSouth13,TSouth20,TSouth21,TSouth22,TSouth30,TSouth31,TSouth40,LSouth00,LSouth01,LSouth02,LSouth03,LSouth04,LSouth10,LSouth11,LSouth12,LSouth13,LSouth20,LSouth21,LSouth22,LSouth30,LSouth31,LSouth40,JEast000,JEast001,JEast002,JEast003,JEast010,JEast011,JEast012,JEast020,JEast021,JEast030,JEast100,JEast101,JEast102,JEast110,JEast111,JEast120,JEast200,JEast201,JEast210,JEast300,TEast000,TEast001,TEast002,TEast003,TEast010,TEast011,TEast012,TEast020,TEast021,TEast030,TEast100,TEast101,TEast102,TEast110,TEast111,TEast120,TEast200,TEast201,TEast210,TEast300,LEast000,LEast001,LEast002,LEast003,LEast010,LEast011,LEast012,LEast020,LEast021,LEast030,LEast100,LEast101,LEast102,LEast110,LEast111,LEast120,LEast200,LEast201,LEast210,LEast300,JWest000,JWest001,JWest002,JWest003,JWest010,JWest011,JWest012,JWest020,JWest021,JWest030,JWest100,JWest101,JWest102,JWest110,JWest111,JWest120,JWest200,JWest201,JWest210,JWest300,TWest000,TWest001,TWest002,TWest003,TWest010,TWest011,TWest012,TWest020,TWest021,TWest030,TWest100,TWest101,TWest102,TWest110,TWest111,TWest120,TWest200,TWest201,TWest210,TWest300,LWest000,LWest001,LWest002,LWest003,LWest010,LWest011,LWest012,LWest020,LWest021,LWest030,LWest100,LWest101,LWest102,LWest110,LWest111,LWest120,LWest200,LWest201,LWest210,LWest300,O00,O01,O02,O03,O04,O10,O11,O12,O13,O20,O21,O22,O30,O31,O40,}
const PIECE_BITS: &'static [u64; 316] = &[6147,6291459,6442450947,6597069766659,6755399441055747,6294528,6442454016,6597069769728,6755399441058816,6445596672,6597072912384,6755399444201472,6600290992128,6755402662281216,6758697975939072,1051650,1073744898,1099511630850,1125899906845698,1076887554,1099514773506,1125899909988354,1102732853250,1125903128068098,1129198441725954,1076889600,1099514775552,1125899909990400,1102732855296,1125903128070144,1129198441728000,1102734950400,1125903130165248,1129198443823104,1129200589209600,3078,3145734,3221225478,3298534883334,3377699720527878,3151872,3221231616,3298534889472,3377699720534016,3227516928,3298541174784,3377699726819328,3304977334272,3377706162978816,3384296790294528,2100225,2147486721,2199023258625,2251799813688321,2150629377,2199026401281,2251799816830977,2202244481025,2251803034910721,2255098348568577,2150630400,2199026402304,2251799816832000,2202244482048,2251803034911744,2255098348569600,2202245529600,2251803035959296,2255098349617152,2255099422310400,15,15360,15728640,16106127360,16492674416640,16888498602639360,1074791425,1099512677377,1125899907892225,1100585370625,1125900980585473,1126999418471425,1100586418177,1125900981633025,1126999419518977,1127000492212225,1100586419200,1125900981634048,1126999419520000,1127000492213248,1127000493260800,1031,1048583,1073741831,1099511627783,1125899906842631,1055744,1073748992,1099511634944,1125899906849792,1081081856,1099518967808,1125899914182656,1107027820544,1125907423035392,1133596488237056,2055,2097159,2147483655,2199023255559,2251799813685255,2104320,2147490816,2199023262720,2251799813692416,2154823680,2199030595584,2251799821025280,2206539448320,2251807329878016,2259496395079680,4103,4194311,4294967303,4398046511111,4503599627370503,4201472,4294974464,4398046518272,4503599627377664,4302307328,4398053851136,4503599634710528,4405562703872,4503607143563264,4511296208764928,7172,7340036,7516192772,7696581394436,7881299347898372,7344128,7516196864,7696581398528,7881299347902464,7520387072,7696585588736,7881299352092672,7700876361728,7881303642865664,7885697394409472,7170,7340034,7516192770,7696581394434,7881299347898370,7342080,7516194816,7696581396480,7881299347900416,7518289920,7696583491584,7881299349995520,7698728878080,7881301495382016,7883498371153920,7169,7340033,7516192769,7696581394433,7881299347898369,7341056,7516193792,7696581395456,7881299347899392,7517241344,7696582443008,7881299348946944,7697655136256,7881300421640192,7882398859526144,3146753,3221226497,3298534884353,3377699720528897,3222274049,3298535931905,3377699721576449,3299608625153,3377700794269697,3378799232155649,3222275072,3298535932928,3377699721577472,3299608626176,3377700794270720,3378799232156672,3299609673728,3377700795318272,3378799233204224,3378800305897472,1051649,1073744897,1099511630849,1125899906845697,1076887553,1099514773505,1125899909988353,1102732853249,1125903128068097,1129198441725953,1076888576,1099514774528,1125899909989376,1102732854272,1125903128069120,1129198441726976,1102733901824,1125903129116672,1129198442774528,1129199515467776,1049603,1073742851,1099511628803,1125899906843651,1074790403,1099512676355,1125899907891203,1100585369603,1125900980584451,1126999418470403,1074793472,1099512679424,1125899907894272,1100585372672,1125900980587520,1126999418473472,1100588515328,1125900983730176,1126999421616128,1127002639695872,2099203,2147485699,2199023257603,2251799813687299,2149580803,2199025352707,2251799815782403,2201170739203,2251801961168899,2253998836940803,2149583872,2199025355776,2251799815785472,2201170742272,2251801961171968,2253998836943872,2201173884928,2251801964314624,2253998840086528,2254002058166272,2100226,2147486722,2199023258626,2251799813688322,2150629378,2199026401282,2251799816830978,2202244481026,2251803034910722,2255098348568578,2150631424,2199026403328,2251799816833024,2202244483072,2251803034912768,2255098348570624,2202246578176,2251803037007872,2255098350665728,2255100496052224,3147778,3221227522,3298534885378,3377699720529922,3223322626,3298536980482,3377699722625026,3300682366978,3377701868011522,3379898743783426,3223324672,3298536982528,3377699722627072,3300682369024,3377701868013568,3379898743785472,3300684464128,3377701870108672,3379898745880576,3379900891267072,3075,3145731,3221225475,3298534883331,3377699720527875,3148800,3221228544,3298534886400,3377699720530944,3224371200,3298538029056,3377699723673600,3301756108800,3377702941753344,3380998255411200,];
const PIECE_HURDLES: &'static [u8; 316] = &[0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,0,4,12,28,2,10,26,6,22,14,0,8,24,4,20,12,0,16,8,0,0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,0,4,12,28,2,10,26,6,22,14,0,8,24,4,20,12,0,16,8,0,0,0,0,0,0,0,0,8,24,4,20,12,2,18,10,6,0,16,8,4,0,0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,0,4,12,28,2,10,26,6,22,14,0,8,24,4,20,12,0,16,8,0,0,4,12,28,2,10,26,6,22,14,0,8,24,4,20,12,0,16,8,0,0,4,12,28,2,10,26,6,22,14,0,8,24,4,20,12,0,16,8,0,0,4,12,28,2,10,26,6,22,14,0,8,24,4,20,12,0,16,8,0,0,4,12,28,2,10,26,6,22,14,0,8,24,4,20,12,0,16,8,0,0,4,12,28,2,10,26,6,22,14,0,8,24,4,20,12,0,16,8,0,0,2,6,14,30,0,4,12,28,0,8,24,0,16,0,];
const PIECE_WIDTHS: &'static [u8; 316] = &[3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,4,4,4,4,4,4,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,];
const PIECE_BELOW: &'static [u64; 316] = &[6,6,6,6,6,6147,6147,6147,6147,6294528,6294528,6294528,6445596672,6445596672,6600290992128,1027,1027,1027,1027,1048579,1048579,1048579,1073741827,1073741827,1099511627779,1051650,1051650,1051650,1073744898,1073744898,1099511630850,1076889600,1076889600,1099514775552,1102734950400,3,3,3,3,3,3078,3078,3078,3078,3151872,3151872,3151872,3227516928,3227516928,3304977334272,2051,2051,2051,2051,2097155,2097155,2097155,2147483651,2147483651,2199023255555,2100225,2100225,2100225,2147486721,2147486721,2199023258625,2150630400,2150630400,2199026402304,2202245529600,0,15,15360,15728640,16106127360,16492674416640,1049601,1049601,1049601,1073742849,1073742849,1099511628801,1074790401,1074790401,1099512676353,1100585369601,1074791425,1074791425,1099512677377,1100585370625,1100586419200,1,1,1,1,1,1031,1031,1031,1031,1055744,1055744,1055744,1081081856,1081081856,1107027820544,2,2,2,2,2,2055,2055,2055,2055,2104320,2104320,2104320,2154823680,2154823680,2206539448320,4,4,4,4,4,4103,4103,4103,4103,4201472,4201472,4201472,4302307328,4302307328,4405562703872,7,7,7,7,7,7172,7172,7172,7172,7344128,7344128,7344128,7520387072,7520387072,7700876361728,7,7,7,7,7,7170,7170,7170,7170,7342080,7342080,7342080,7518289920,7518289920,7698728878080,7,7,7,7,7,7169,7169,7169,7169,7341056,7341056,7341056,7517241344,7517241344,7697655136256,3073,3073,3073,3073,3145729,3145729,3145729,3221225473,3221225473,3298534883329,3146753,3146753,3146753,3221226497,3221226497,3298534884353,3222275072,3222275072,3298535932928,3299609673728,1027,1027,1027,1027,1048579,1048579,1048579,1073741827,1073741827,1099511627779,1051649,1051649,1051649,1073744897,1073744897,1099511630849,1076888576,1076888576,1099514774528,1102733901824,1025,1025,1025,1025,1048577,1048577,1048577,1073741825,1073741825,1099511627777,1049603,1049603,1049603,1073742851,1073742851,1099511628803,1074793472,1074793472,1099512679424,1100588515328,2050,2050,2050,2050,2097154,2097154,2097154,2147483650,2147483650,2199023255554,2099203,2099203,2099203,2147485699,2147485699,2199023257603,2149583872,2149583872,2199025355776,2201173884928,2051,2051,2051,2051,2097155,2097155,2097155,2147483651,2147483651,2199023255555,2100226,2100226,2100226,2147486722,2147486722,2199023258626,2150631424,2150631424,2199026403328,2202246578176,3074,3074,3074,3074,3145730,3145730,3145730,3221225474,3221225474,3298534883330,3147778,3147778,3147778,3221227522,3221227522,3298534885378,3223324672,3223324672,3298536982528,3300684464128,3,3,3,3,3,3075,3075,3075,3075,3148800,3148800,3148800,3224371200,3224371200,3301756108800,];
const PIECE_HARDDROP: &'static [u64; 316] = &[7889003452832771,7889003452825603,7889003445485571,7888995929292803,7881299347898371,7889003452828672,7889003445488640,7888995929295872,7881299347901440,7889003448631296,7888995932438528,7881299351044096,7888999150518272,7881302569123840,7884597882781696,3381001479785474,3381001476639746,3380998255414274,3377699720530946,3381001479782402,3380998258556930,3377699723673602,3381001476636674,3377702941753346,3380998255411202,3381001479784448,3380998258558976,3377699723675648,3381001476638720,3377702941755392,3380998255413248,3381001478733824,3377702943850496,3380998257508352,3381000402894848,7889003452832774,7889003452825606,7889003445485574,7888995929292806,7881299347898374,7889003452831744,7889003445491712,7888995929298944,7881299347904512,7889003451777024,7888995935584256,7881299354189824,7889002371743744,7881305790349312,7887896417665024,3381001479785473,3381001476639745,3380998255414273,3377699720530945,3381001479782401,3380998258556929,3377699723673601,3381001476636673,3377702941753345,3380998255411201,3381001479783424,3380998258557952,3377699723674624,3381001476637696,3377702941754368,3380998255412224,3381001477685248,3377702942801920,3380998256459776,3380999329153024,16905007398927375,16905007398927360,16905007398912000,16905007383183360,16904991277056000,16888498602639360,1127000493261825,1126999419520001,1125899907892225,1127000492213249,1125900980585473,1126999418471425,1127000493260801,1125900981633025,1126999419518977,1127000492212225,1127000493261824,1125900981634048,1126999419520000,1127000492213248,1127000493260800,7889003452832775,7889003452825607,7889003445485575,7888995929292807,7881299347898375,7889003452832768,7889003445492736,7888995929299968,7881299347905536,7889003452825600,7888995936632832,7881299355238400,7889003445485568,7881306864091136,7888995929292800,7889003452832775,7889003452825607,7889003445485575,7888995929292807,7881299347898375,7889003452832768,7889003445492736,7888995929299968,7881299347905536,7889003452825600,7888995936632832,7881299355238400,7889003445485568,7881306864091136,7888995929292800,7889003452832775,7889003452825607,7889003445485575,7888995929292807,7881299347898375,7889003452832768,7889003445492736,7888995929299968,7881299347905536,7889003452825600,7888995936632832,7881299355238400,7889003445485568,7881306864091136,7888995929292800,7889003452832772,7889003452825604,7889003445485572,7888995929292804,7881299347898372,7889003452829696,7889003445489664,7888995929296896,7881299347902464,7889003449679872,7888995933487104,7881299352092672,7889000224260096,7881303642865664,7885697394409472,7889003452832770,7889003452825602,7889003445485570,7888995929292802,7881299347898370,7889003452827648,7889003445487616,7888995929294848,7881299347900416,7889003447582720,7888995931389952,7881299349995520,7888998076776448,7881301495382016,7883498371153920,7889003452832769,7889003452825601,7889003445485569,7888995929292801,7881299347898369,7889003452826624,7889003445486592,7888995929293824,7881299347899392,7889003446534144,7888995930341376,7881299348946944,7888997003034624,7881300421640192,7882398859526144,3381001479783425,3381001476637697,3380998255412225,3377699720528897,3381001477685249,3380998256459777,3377699721576449,3380999329153025,3377700794269697,3378799232155649,3381001477686272,3380998256460800,3377699721577472,3380999329154048,3377700794270720,3378799232156672,3380999330201600,3377700795318272,3378799233204224,3378800305897472,3381001479785473,3381001476639745,3380998255414273,3377699720530945,3381001479782401,3380998258556929,3377699723673601,3381001476636673,3377702941753345,3380998255411201,3381001479783424,3380998258557952,3377699723674624,3381001476637696,3377702941754368,3380998255412224,3381001477685248,3377702942801920,3380998256459776,3380999329153024,3381001479785475,3381001476639747,3380998255414275,3377699720530947,3381001479782403,3380998258556931,3377699723673603,3381001476636675,3377702941753347,3380998255411203,3381001479785472,3380998258560000,3377699723676672,3381001476639744,3377702941756416,3380998255414272,3381001479782400,3377702944899072,3380998258556928,3381001476636672,3381001479785475,3381001476639747,3380998255414275,3377699720530947,3381001479782403,3380998258556931,3377699723673603,3381001476636675,3377702941753347,3380998255411203,3381001479785472,3380998258560000,3377699723676672,3381001476639744,3377702941756416,3380998255414272,3381001479782400,3377702944899072,3380998258556928,3381001476636672,3381001479785474,3381001476639746,3380998255414274,3377699720530946,3381001479782402,3380998258556930,3377699723673602,3381001476636674,3377702941753346,3380998255411202,3381001479784448,3380998258558976,3377699723675648,3381001476638720,3377702941755392,3380998255413248,3381001478733824,3377702943850496,3380998257508352,3381000402894848,3381001479784450,3381001476638722,3380998255413250,3377699720529922,3381001478733826,3380998257508354,3377699722625026,3381000402894850,3377701868011522,3379898743783426,3381001478735872,3380998257510400,3377699722627072,3381000402896896,3377701868013568,3379898743785472,3381000404992000,3377701870108672,3379898745880576,3379900891267072,3381001479785475,3381001479782403,3381001476636675,3380998255411203,3377699720527875,3381001479785472,3381001476639744,3380998255414272,3377699720530944,3381001479782400,3380998258556928,3377699723673600,3381001476636672,3377702941753344,3380998255411200,];
const PIECE_Y: &'static [u8; 316] = &[0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,3,0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,3,0,1,2,3,4,5,0,0,0,0,0,0,0,0,0,0,1,1,1,1,2,0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,3,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,3,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,3,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,3,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,3,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,2,2,2,3,0,0,0,0,0,1,1,1,1,2,2,2,3,3,4,];
const PIECE_KINDS: &'static [Piece; 316] = &[Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::S,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::Z,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::I,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::J,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::T,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::L,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,Piece::O,];
const PIECE_SRS: &'static [&'static [SrsPiece]; 316] = &[&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::North,
                x: 1, y: 4
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::South,
                x: 1, y: 5
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::S,
                rotation: Rotation::West,
                x: 1, y: 4
            },SrsPiece {
                piece: Piece::S,
                rotation: Rotation::East,
                x: 0, y: 4
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::North,
                x: 1, y: 4
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::South,
                x: 1, y: 5
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::West,
                x: 1, y: 4
            },SrsPiece {
                piece: Piece::Z,
                rotation: Rotation::East,
                x: 0, y: 4
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::North,
                x: 1, y: 0
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::South,
                x: 2, y: 0
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::North,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::South,
                x: 2, y: 1
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::North,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::South,
                x: 2, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::North,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::South,
                x: 2, y: 3
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::North,
                x: 1, y: 4
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::South,
                x: 2, y: 4
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::North,
                x: 1, y: 5
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::South,
                x: 2, y: 5
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::I,
                rotation: Rotation::West,
                x: 0, y: 3
            },SrsPiece {
                piece: Piece::I,
                rotation: Rotation::East,
                x: 0, y: 4
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::North,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::North,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::North,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::South,
                x: 1, y: 5
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::South,
                x: 1, y: 5
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::South,
                x: 1, y: 5
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::East,
                x: 0, y: 4
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::East,
                x: 0, y: 4
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::East,
                x: 0, y: 4
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::J,
                rotation: Rotation::West,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::T,
                rotation: Rotation::West,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::L,
                rotation: Rotation::West,
                x: 1, y: 4
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 0
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 0
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 0
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 0
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 0
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 0
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 1
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 1
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 3
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 3
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 2
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 3
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 3
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 2
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 3
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 4
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 4
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 3
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 4
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 4
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 3
            },],&[SrsPiece {
                piece: Piece::O,
                rotation: Rotation::North,
                x: 0, y: 4
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::East,
                x: 0, y: 5
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::South,
                x: 1, y: 5
            },SrsPiece {
                piece: Piece::O,
                rotation: Rotation::West,
                x: 1, y: 4
            },],];
impl PieceState
{
    #[inline] pub fn board(self) -> crate::BitBoard
    { BitBoard(PIECE_BITS[self as usize]) } #[inline] pub fn width(self) -> u8
    { PIECE_WIDTHS[self as usize] } #[inline] pub fn hurdles(self) -> u8
    { PIECE_HURDLES[self as usize] } #[inline] pub fn below_mask(self) ->
    BitBoard { BitBoard(PIECE_BELOW[self as usize]) } #[inline] pub fn
    harddrop_mask(self) -> BitBoard
    { BitBoard(PIECE_HARDDROP[self as usize]) } #[inline] pub fn y(self) -> u8
    { PIECE_Y[self as usize] } #[inline] pub fn piece(self) -> Piece
    { PIECE_KINDS[self as usize] } #[inline] pub fn piece_srs(self) ->
    &'static [SrsPiece] { PIECE_SRS[self as usize] }
}
}
