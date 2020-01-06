!..................................................................................................................................
! LICENSING
! Copyright (C) 2013-2016  National Renewable Energy Laboratory
!
!    This file is part of SubDyn.
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!**********************************************************************************************************************************
MODULE SD_FEM
  USE NWTC_Library
  USE SubDyn_Types
  USE FEM
  IMPLICIT NONE

 
  INTEGER(IntKi),   PARAMETER  :: MaxMemJnt       = 10                    ! Maximum number of members at one joint
  INTEGER(IntKi),   PARAMETER  :: MaxOutChs       = 2000                  ! Max number of Output Channels to be read in
  INTEGER(IntKi),   PARAMETER  :: TPdofL          = 6                     ! 6 degrees of freedom (length of u subarray [UTP])
   
  ! values of these parameters are ordered by their place in SubDyn input file:
  INTEGER(IntKi),   PARAMETER  :: JointsCol       = 10                    ! Number of columns in Joints (JointID, JointXss, JointYss, JointZss)
  INTEGER(IntKi),   PARAMETER  :: ReactCol        = 7                     ! Number of columns in reaction dof array (JointID,RctTDxss,RctTDYss,RctTDZss,RctRDXss,RctRDYss,RctRDZss)
  INTEGER(IntKi),   PARAMETER  :: InterfCol       = 7                     ! Number of columns in interf matrix (JointID,ItfTDxss,ItfTDYss,ItfTDZss,ItfRDXss,ItfRDYss,ItfRDZss)
  INTEGER(IntKi),   PARAMETER  :: MaxNodesPerElem = 2                     ! Maximum number of nodes per element (currently 2)
  INTEGER(IntKi),   PARAMETER  :: MembersCol      = MaxNodesPerElem + 3+1 ! Number of columns in Members (MemberID,MJointID1,MJointID2,MPropSetID1,MPropSetID2,COSMID) 
  INTEGER(IntKi),   PARAMETER  :: PropSetsBCol    = 6                     ! Number of columns in PropSets  (PropSetID,YoungE,ShearG,MatDens,XsecD,XsecT)  !bjj: this really doesn't need to store k, does it? or is this supposed to be an ID, in which case we shouldn't be storing k (except new property sets), we should be storing IDs
  INTEGER(IntKi),   PARAMETER  :: PropSetsXCol    = 10                    ! Number of columns in XPropSets (PropSetID,YoungE,ShearG,MatDens,XsecA,XsecAsx,XsecAsy,XsecJxx,XsecJyy,XsecJ0)
  INTEGER(IntKi),   PARAMETER  :: PropSetsCCol    = 4                     ! Number of columns in CablePropSet (PropSetID, EA, MatDens, T0)
  INTEGER(IntKi),   PARAMETER  :: PropSetsRCol    = 2                     ! Number of columns in RigidPropSet (PropSetID, MatDens)
  INTEGER(IntKi),   PARAMETER  :: COSMsCol        = 10                    ! Number of columns in (cosine matrices) COSMs (COSMID,COSM11,COSM12,COSM13,COSM21,COSM22,COSM23,COSM31,COSM32,COSM33)
  INTEGER(IntKi),   PARAMETER  :: CMassCol        = 5                     ! Number of columns in Concentrated Mass (CMJointID,JMass,JMXX,JMYY,JMZZ)
  ! Indices in Members table
  INTEGER(IntKi),   PARAMETER  :: iMType= 6 ! Index in Members table where the type is stored
  INTEGER(IntKi),   PARAMETER  :: iMProp= 4 ! Index in Members table where the PropSet1 and 2 are stored

  ! Indices in Joints table
  INTEGER(IntKi),   PARAMETER  :: iJointType= 5  ! Index in Joints where the joint type is stored
  INTEGER(IntKi),   PARAMETER  :: iJointDir= 6 ! Index in Joints where the joint-direction are stored
  INTEGER(IntKi),   PARAMETER  :: iJointStiff= 9 ! Index in Joints where the joint-stiffness is stored
  INTEGER(IntKi),   PARAMETER  :: iJointDamp= 10 ! Index in Joints where the joint-damping is stored

  ! ID for joint types
  INTEGER(IntKi),   PARAMETER  :: idJointCantilever = 1
  INTEGER(IntKi),   PARAMETER  :: idJointUniversal  = 2
  INTEGER(IntKi),   PARAMETER  :: idJointPin        = 3
  INTEGER(IntKi),   PARAMETER  :: idJointBall       = 4

  ! ID for member types
  INTEGER(IntKi),   PARAMETER  :: idMemberBeam       = 1
  INTEGER(IntKi),   PARAMETER  :: idMemberCable      = 2
  INTEGER(IntKi),   PARAMETER  :: idMemberRigid      = 3
  
  INTEGER(IntKi),   PARAMETER  :: SDMaxInpCols    = MAX(JointsCol,ReactCol,InterfCol,MembersCol,PropSetsBCol,PropSetsXCol,COSMsCol,CMassCol)

  INTERFACE FINDLOCI ! In the future, use FINDLOC from intrinsic
     MODULE PROCEDURE FINDLOCI_ReKi
     MODULE PROCEDURE FINDLOCI_IntKi
  END INTERFACE


CONTAINS
!------------------------------------------------------------------------------------------------------
! --- Helper functions
!------------------------------------------------------------------------------------------------------
!> Maps nodes to elements 
!! allocate NodesConnE and NodesConnN                                                                               
SUBROUTINE NodeCon(Init,p, ErrStat, ErrMsg)
  USE qsort_c_module ,only: QsortC
  TYPE(SD_InitType),              INTENT( INOUT ) :: Init
  TYPE(SD_ParameterType),         INTENT( IN    ) :: p
  INTEGER(IntKi),                 INTENT(   OUT ) :: ErrStat     ! Error status of the operation
  CHARACTER(*),                   INTENT(   OUT ) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
  ! Local variables
  INTEGER(IntKi) :: SortA(MaxMemJnt,1)  !To sort nodes and elements
  INTEGER(IntKi) :: I,J,K  !counter
  
  ! The row index is the number of the real node, i.e. ID, 1st col has number of elements attached to node, and 2nd col has element numbers (up to 10)                                    
  CALL AllocAry(Init%NodesConnE, Init%NNode, MaxMemJnt+1,'NodesConnE', ErrStat, ErrMsg); if (ErrStat/=0) return;
  CALL AllocAry(Init%NodesConnN, Init%NNode, MaxMemJnt+2,'NodesConnN', ErrStat, ErrMsg); if (ErrStat/=0) return;
  Init%NodesConnE = 0                                                                                                    
  Init%NodesConnN = -99999 ! Not Used
                                                                                                                          
   ! find the node connectivity, nodes/elements that connect to a common node                                             
   DO I = 1, Init%NNode                                                                                                   
      !Init%NodesConnN(I, 1) = NINT( Init%Nodes(I, 1) )      !This should not be needed, could remove the extra 1st column like for the other array                                                                      
      k = 0                                                                                                               
      DO J = 1, Init%NElem                          !This should be vectorized                                                                      
         IF ( ( NINT(Init%Nodes(I, 1))==p%Elems(J, 2)) .OR. (NINT(Init%Nodes(I, 1))==p%Elems(J, 3) ) ) THEN   !If i-th nodeID matches 1st node or 2nd of j-th element                                                                   
            k = k + 1                                                                                                     
            if (k > MaxMemJnt+1) then 
               CALL SetErrStat(ErrID_Fatal, 'Maximum number of members reached on node'//trim(Num2LStr(NINT(Init%Nodes(I,1)))), ErrStat, ErrMsg, 'NodeCon');
            endif
            Init%NodesConnE(I, k + 1) = p%Elems(J, 1)                                                                  
            !if ( NINT(Init%Nodes(I, 1))==p%Elems(J, 3) ) then
            !   Init%NodesConnN(I, k + 1) = p%Elems(J, 2)     !If nodeID matches 2nd node of element                                                                
            !else
            !   Init%NodesConnN(I, k + 1) = p%Elems(J, 3)                                                                  
            !endif
         ENDIF                                                                                                            
      ENDDO                                                                                                               
                                                                                                                          
      !IF( k>1 )THEN ! sort the nodes ascendingly                                                                          
      !   SortA(1:k, 1) = Init%NodesConnN(I, 3:(k+2))  
      !   CALL QsortC( SortA(1:k, 1:1) )                                                                                   
      !   Init%NodesConnN(I, 3:(k+2)) = SortA(1:k, 1)                                                                      
      !ENDIF                                                                                                               
                                                                                                                          
      Init%NodesConnE(I, 1) = k    !Store how many elements connect i-th node in 2nd column                                                                                       
      !Init%NodesConnN(I, 2) = k                                                                                           
      !print*,'ConnE',I,'val',Init%NodesConnE(I, 1:5)
   ENDDO                            

END SUBROUTINE NodeCon

!----------------------------------------------------------------------------
!> Check if two elements are connected
!! returns true if they are, and return which node (1 or 2) of each element is involved
LOGICAL FUNCTION ElementsConnected(p, ie1, ie2, iWhichNode_e1, iWhichNode_e2)
   TYPE(SD_ParameterType),       INTENT(IN)  :: p
   INTEGER(IntKi),               INTENT(IN)  :: ie1, ie2 ! Indices of elements
   INTEGER(IntKi),               INTENT(OUT) :: iWhichNode_e1, iWhichNode_e2 ! 1 or 2 if node 1 or node 2
   if      ((p%Elems(ie1, 2) == p%Elems(ie2, 2))) then ! node 1 connected to node 1
      iWhichNode_e1=1
      iWhichNode_e2=1
      ElementsConnected=.True.
   else if((p%Elems(ie1, 2) == p%Elems(ie2, 3))) then  ! node 1 connected to node 2
      iWhichNode_e1=1
      iWhichNode_e2=2
      ElementsConnected=.True.
   else if((p%Elems(ie1, 3) == p%Elems(ie2, 2))) then  ! node 2 connected to node 1
      iWhichNode_e1=2
      iWhichNode_e2=1
      ElementsConnected=.True.
   else if((p%Elems(ie1, 3) == p%Elems(ie2, 3))) then  ! node 2 connected to node 2
      iWhichNode_e1=2
      iWhichNode_e2=2
      ElementsConnected=.True.
   else
      ElementsConnected=.False.
      iWhichNode_e1=-1
      iWhichNode_e2=-1
   endif
END FUNCTION ElementsConnected

!> Loop through a list of elements and returns a list of unique joints
TYPE(IList) FUNCTION NodesList(p, Elements)
   use IntegerList, only: init_list, append, find, sort
   use IntegerList, only: print_list
   TYPE(SD_ParameterType),       INTENT(IN)  :: p
   integer(IntKi), dimension(:), INTENT(IN)  :: Elements
   integer(IntKi)  :: ie, ei, j1, j2
   INTEGER(IntKi)  :: ErrStat2
   CHARACTER(ErrMsgLen) :: ErrMsg2

   call init_list(NodesList, 0, 0, ErrStat2, ErrMsg2)
   do ie = 1, size(Elements)
      ei = Elements(ie)  ! Element index
      j1 = p%Elems(ei,2) ! Joint 1 
      j2 = p%Elems(ei,3) ! Joint 2
      ! Append joints indices if not in list already
      if (find(NodesList, j1, ErrStat2, ErrMsg2)<=0) call append(NodesList, j1, ErrStat2, ErrMsg2)
      if (find(NodesList, j2, ErrStat2, ErrMsg2)<=0) call append(NodesList, j2, ErrStat2, ErrMsg2)
      ! Sorting required by find function
      call sort(NodesList, ErrStat2, ErrMsg2)
   enddo
   call print_list(NodesList, 'Joint list')
END FUNCTION NodesList
!------------------------------------------------------------------------------------------------------
!> Returns list of rigid link elements (Er) 
TYPE(IList) FUNCTION RigidLinkElements(Init, p, ErrStat, ErrMsg)
   use IntegerList, only: init_list, append
   use IntegerList, only: print_list
   TYPE(SD_InitType),            INTENT(INOUT) :: Init
   TYPE(SD_ParameterType),       INTENT(INOUT) :: p
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   ! Local variables
   integer(IntKi)  :: ie       !< Index on elements
   ErrStat = ErrID_None
   ErrMsg  = ""
   ! --- Establish a list of rigid link elements
   call init_list(RigidLinkElements, 0, 0, ErrStat, ErrMsg);

   do ie = 1, Init%NElem
      if (p%ElemProps(ie)%eType == idMemberRigid) then
         call append(RigidLinkElements, ie, ErrStat, ErrMsg);
      endif
   end do
   call print_list(RigidLinkElements,'Rigid element list')
END FUNCTION RigidLinkElements

!------------------------------------------------------------------------------------------------------
!> Returns true if one of the element connected to the node is a rigid link
LOGICAL FUNCTION NodeHasRigidElem(iJoint, Init, p)
   INTEGER(IntKi),               INTENT(IN) :: iJoint  
   TYPE(SD_InitType),            INTENT(IN) :: Init
   TYPE(SD_ParameterType),       INTENT(IN) :: p
   ! Local variables
   integer(IntKi) :: ie       !< Loop index on elements
   integer(IntKi) :: ei       !< Element index
   integer(IntKi) :: m  ! Number of elements connected to a joint

   NodeHasRigidElem = .False. ! default return value

   ! Loop through elements connected to node J 
   do ie = 1, Init%NodesConnE(iJoint, 1)
      ei = Init%NodesConnE(iJoint, ie+1)
      if (p%ElemProps(ei)%eType == idMemberRigid) then
         NodeHasRigidElem = .True.
         return  ! we exit as soon as one rigid member is found
      endif
   enddo
END FUNCTION NodeHasRigidElem

!------------------------------------------------------------------------------------------------------
! --- Main routines, more or less listed in order in which they are called
!------------------------------------------------------------------------------------------------------
!>
! - Removes the notion of "ID" and use Index instead
! - Creates Nodes (use indices instead of ID), similar to Joints array
! - Creates Elems (use indices instead of ID)  similar to Members array
! - Updates Reacts (use indices instead of ID)
! - Updates Interf (use indices instead of ID)
SUBROUTINE SD_ReIndex_CreateNodesAndElems(Init,p, ErrStat, ErrMsg)
   TYPE(SD_InitType),            INTENT(INOUT)  ::Init
   TYPE(SD_ParameterType),       INTENT(INOUT)  ::p
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   ! local variable
   INTEGER                       :: I, n, iMem, iNode, JointID   
   INTEGER(IntKi)                :: mType !< Member Type
   CHARACTER(1255)               :: sType !< String for element type
   INTEGER(IntKi)                :: ErrStat2
   CHARACTER(ErrMsgLen)          :: ErrMsg2
   ErrStat = ErrID_None
   ErrMsg  = ""

   ! TODO See if Elems is actually used elsewhere

   CALL AllocAry(p%Elems,         Init%NElem,    MembersCol, 'p%Elems',         ErrStat2, ErrMsg2); if(Failed()) return
   CALL AllocAry(Init%Nodes,      Init%NNode,    JointsCol,  'Init%Nodes',      ErrStat2, ErrMsg2); if(Failed()) return

   ! --- Initialize Nodes
   Init%Nodes = -999999 ! Init to unphysical values
   do I = 1,Init%NJoints
      Init%Nodes(I, 1) = I                                     ! JointID replaced by index I
      Init%Nodes(I, 2:JointsCol) = Init%Joints(I, 2:JointsCol) ! All the rest is copied
   enddo

   ! --- Re-Initialize Reactions, pointing to index instead of JointID
   do I = 1, p%NReact
      JointID=p%Reacts(I,1)
      p%Reacts(I,1) = FINDLOCI(Init%Joints(:,1), JointID ) ! Replace JointID with Index
      if (p%Reacts(I,1)<=0) then
         CALL Fatal('Reaction joint table: line '//TRIM(Num2LStr(I))//' refers to JointID '//trim(Num2LStr(JointID))//' which is not in the joint list!')
         return
      endif
   enddo

   ! --- Re-Initialize interface joints, pointing to index instead of JointID
   do I = 1, Init%NInterf
      JointID=Init%Interf(I,1)
      Init%Interf(I,1) = FINDLOCI(Init%Joints(:,1), JointID )
      if (Init%Interf(I,1)<=0) then
         CALL Fatal('Interface joint table: line '//TRIM(Num2LStr(I))//' refers to JointID '//trim(Num2LStr(JointID))//' which is not in the joint list!')
         return
      endif
   enddo

   ! Change numbering in concentrated mass matrix
   do I = 1, Init%NCMass
      JointID = Init%CMass(I,1)
      Init%CMass(I,1) = FINDLOCI(Init%Joints(:,1), JointID )
      if (Init%CMass(I,1)<=0) then
         CALL Fatal('Concentrated mass table: line '//TRIM(Num2LStr(I))//' refers to JointID '//trim(Num2LStr(JointID))//' which is not in the joint list!')
         return
      endif
   enddo


   ! --- Initialize Elems, starting with each member as an element (we'll take NDiv into account later)
   p%Elems = 0
   ! --- Replacing "MemberID"  "JointID", and "PropSetID" by simple index in this tables
   DO iMem = 1, p%NMembers
      ! Column 1  : member index (instead of MemberID)
      p%Elems(iMem,     1)  = iMem
      mType =  Init%Members(iMem, iMType) ! 
      ! Column 2-3: Joint index (instead of JointIDs)
      p%Elems(iMem,     1)  = iMem  ! NOTE: element/member number (not MemberID)
      do iNode=2,3
         p%Elems(iMem,iNode) = FINDLOCI(Init%Joints(:,1), Init%Members(iMem, iNode) ) 
         if (p%Elems(iMem,iNode)<=0) then
            CALL Fatal(' MemberID '//TRIM(Num2LStr(Init%Members(iMem,1)))//' has JointID'//TRIM(Num2LStr(iNode-1))//' = '// TRIM(Num2LStr(Init%Members(iMem, iNode)))//' which is not in the joint list!')
            return
         endif
      enddo
      ! Column 4-5: PropIndex 1-2 (instead of PropSetID1&2)
      ! NOTE: this index has different meaning depending on the member type !
      DO n=iMProp,iMProp+1

         if (mType==idMemberBeam) then
            sType='Member x-section property'
            p%Elems(iMem,n) = FINDLOCI(Init%PropSetsB(:,1), Init%Members(iMem, n) ) 
         else if (mType==idMemberCable) then
            sType='Cable property'
            p%Elems(iMem,n) = FINDLOCI(Init%PropSetsC(:,1), Init%Members(iMem, n) ) 
         else if (mType==idMemberRigid) then
            sType='Rigid property'
            p%Elems(iMem,n) = FINDLOCI(Init%PropSetsR(:,1), Init%Members(iMem, n) ) 
         else
            ! Should not happen
            print*,'Element type unknown',mType
            STOP
         end if

         if (p%Elems(iMem,n)<=0) then
            CALL Fatal('For MemberID '//TRIM(Num2LStr(Init%Members(iMem,1)))//', the PropSetID'//TRIM(Num2LStr(n-3))//' is not in the'//trim(sType)//' table!')
         endif
      END DO !n, loop through property ids         
      ! Column 6: member type
      p%Elems(iMem, iMType) = Init%Members(iMem, iMType) ! 
   END DO !iMem, loop through members
    
   ! TODO in theory, we shouldn't need these anymore
   ! deallocate(Init%Members)
   ! deallocate(Init%Joints)
CONTAINS
   LOGICAL FUNCTION Failed()
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'SD_ReIndex_CreateNodesAndElems') 
      Failed =  ErrStat >= AbortErrLev
   END FUNCTION Failed
   SUBROUTINE Fatal(ErrMsg_in)
      CHARACTER(len=*), intent(in) :: ErrMsg_in
      CALL SetErrStat(ErrID_Fatal, ErrMsg_in, ErrStat, ErrMsg, 'SD_ReIndex_CreateNodesAndElems');
   END SUBROUTINE Fatal
END SUBROUTINE SD_ReIndex_CreateNodesAndElems

!----------------------------------------------------------------------------
SUBROUTINE SD_Discrt(Init,p, ErrStat, ErrMsg)
   TYPE(SD_InitType),            INTENT(INOUT)  ::Init
   TYPE(SD_ParameterType),       INTENT(INOUT)  ::p
   INTEGER(IntKi),               INTENT(  OUT)  :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   ! local variable
   INTEGER                       :: I, J, n, Node1, Node2, Prop1, Prop2   
   INTEGER                       :: NNE      ! number of nodes per element
   INTEGER                       :: MaxNProp
   REAL(ReKi), ALLOCATABLE       :: TempProps(:, :)
   INTEGER, ALLOCATABLE          :: TempMembers(:, :)
   INTEGER                       :: knode, kelem, kprop, nprop
   REAL(ReKi)                    :: x1, y1, z1, x2, y2, z2, dx, dy, dz, dd, dt, d1, d2, t1, t2
   LOGICAL                       :: found, CreateNewProp
   INTEGER(IntKi)                :: eType !< Element Type
   INTEGER(IntKi)                :: ErrStat2
   CHARACTER(ErrMsgLen)          :: ErrMsg2
   ErrStat = ErrID_None
   ErrMsg  = ""
   
   ! number of nodes per element
   IF( ( Init%FEMMod >= 0 ) .and. (Init%FEMMod <= 3) ) THEN
      NNE = 2 
   ELSE
      CALL Fatal('FEMMod '//TRIM(Num2LStr(Init%FEMMod))//' not implemented.')
      RETURN
   ENDIF
   
   ! Total number of element   
   Init%NElem = p%NMembers*Init%NDiv  ! TODO TODO TODO: THIS IS A MAX SINCE CABLE AND RIGID CANNOT BE SUBDIVIDED
   ! Total number of nodes - Depends on division and number of nodes per element
   Init%NNode = Init%NJoints + ( Init%NDiv - 1 )*p%NMembers 
   Init%NNode = Init%NNode + (NNE - 2)*Init%NElem  ! TODO TODO TODO Same as above. 
   
   ! check the number of interior modes
   IF ( p%Nmodes > 6*(Init%NNode - Init%NInterf - p%NReact) ) THEN
      CALL Fatal(' NModes must be less than or equal to '//TRIM(Num2LStr( 6*(Init%NNode - Init%NInterf - p%NReact) )))
      RETURN
   ENDIF
   
   CALL AllocAry(Init%MemberNodes,p%NMembers,    Init%NDiv+1,'Init%MemberNodes',ErrStat2, ErrMsg2); if(Failed()) return ! for two-node element only, otherwise the number of nodes in one element is different

   ! --- Reindexing JointsID and MembersID into Nodes and Elems arrays
   ! NOTE: need NNode and NElem 
   CALL SD_ReIndex_CreateNodesAndElems(Init,p, ErrStat2, ErrMsg2);  if(Failed()) return
   
  
    Init%MemberNodes = 0
    ! --- Setting up MemberNodes (And Elems, Props, Nodes if divisions)
    if (Init%NDiv==1) then
       ! NDiv = 1
       Init%MemberNodes(1:p%NMembers, 1:2) = p%Elems(1:Init%NElem, 2:3) 
       Init%NPropB = Init%NPropSetsB

    else if (Init%NDiv > 1) then

       ! Discretize structure according to NDiv 
       ! - Elems is fully reinitialized, connectivity needs to be done again using SetNewElem
       ! - Nodes are not  reinitialized, but appended to NNodes
       ! 

       ! Initialize Temp arrays that will contain user inputs + input from the subdivided members
       !  We don't know how many properties will be needed, so allocated to size MaxNProp
       MaxNProp   = Init%NPropSetsB + Init%NElem*NNE ! Maximum possible number of property sets (temp): This is property set per element node, for all elements (bjj, added Init%NPropSets to account for possibility of entering many unused prop sets)
       CALL AllocAry(TempMembers, p%NMembers,    MembersCol , 'TempMembers', ErrStat2, ErrMsg2); if(Failed()) return
       CALL AllocAry(TempProps,  MaxNProp,      PropSetsBCol,'TempProps',  ErrStat2, ErrMsg2); if(Failed()) return
       TempProps = -9999.
       TempMembers                      = p%Elems(1:p%NMembers,:)
       TempProps(1:Init%NPropSetsB, :) = Init%PropSetsB   

       kelem = 0
       knode = Init%NJoints
       kprop = Init%NPropSetsB
       DO I = 1, p%NMembers !the first p%NMembers rows of p%Elems contain the element information
          ! Member data
          Node1 = TempMembers(I, 2)
          Node2 = TempMembers(I, 3)
          Prop1 = TempMembers(I, iMProp  )
          Prop2 = TempMembers(I, iMProp+1)
          eType = TempMembers(I, iMType  )
          
          IF ( Node1==Node2 ) THEN
             CALL Fatal(' Same starting and ending node in the member.')
             RETURN
          ENDIF
          
          if (eType/=idMemberBeam) then
             ! --- Cables and rigid links are not subdivided
             ! No need to create new properties or new nodes
             print*,'Member',I, 'not subdivided since it is not a beam. Looping through.'
             Init%MemberNodes(I, 1) = Node1
             Init%MemberNodes(I, 2) = Node2
             kelem = kelem + 1
             CALL SetNewElem(kelem, Node1, Node2, eType, Prop1, Prop1, p)                

             continue
          endif

          ! --- Subdivision of beams
          Init%MemberNodes(I,           1) = Node1
          Init%MemberNodes(I, Init%NDiv+1) = Node2

          IF  ( ( .not. EqualRealNos(TempProps(Prop1, 2),TempProps(Prop2, 2) ) ) &
           .OR. ( .not. EqualRealNos(TempProps(Prop1, 3),TempProps(Prop2, 3) ) ) &
           .OR. ( .not. EqualRealNos(TempProps(Prop1, 4),TempProps(Prop2, 4) ) ) )  THEN
          
             CALL Fatal(' Material E,G and rho in a member must be the same')
             RETURN
          ENDIF

          x1 = Init%Nodes(Node1, 2)
          y1 = Init%Nodes(Node1, 3)
          z1 = Init%Nodes(Node1, 4)

          x2 = Init%Nodes(Node2, 2)
          y2 = Init%Nodes(Node2, 3)
          z2 = Init%Nodes(Node2, 4)
          
          dx = ( x2 - x1 )/Init%NDiv
          dy = ( y2 - y1 )/Init%NDiv
          dz = ( z2 - z1 )/Init%NDiv
          
          d1 = TempProps(Prop1, 5)
          t1 = TempProps(Prop1, 6)

          d2 = TempProps(Prop2, 5)
          t2 = TempProps(Prop2, 6)
          
          dd = ( d2 - d1 )/Init%NDiv
          dt = ( t2 - t1 )/Init%NDiv
          
             ! If both dd and dt are 0, no interpolation is needed, and we can use the same property set for new nodes/elements. otherwise we'll have to create new properties for each new node
          CreateNewProp = .NOT. ( EqualRealNos( dd , 0.0_ReKi ) .AND.  EqualRealNos( dt , 0.0_ReKi ) )  
          
          ! node connect to Node1
          knode = knode + 1
          Init%MemberNodes(I, 2) = knode
          CALL SetNewNode(knode, x1+dx, y1+dy, z1+dz, Init) ! Set Init%Nodes(knode,:)
          
          IF ( CreateNewProp ) THEN   
               ! create a new property set 
               ! k, E, G, rho, d, t, Init
               kprop = kprop + 1
               CALL SetNewProp(kprop, TempProps(Prop1, 2), TempProps(Prop1, 3), TempProps(Prop1, 4), d1+dd, t1+dt, TempProps)           
               kelem = kelem + 1
               CALL SetNewElem(kelem, Node1, knode, eType, Prop1, kprop, p)  
               nprop = kprop
          ELSE
               kelem = kelem + 1
               CALL SetNewElem(kelem, Node1, knode, eType, Prop1, Prop1, p)                
               nprop = Prop1 
          ENDIF
          
          ! interior nodes
          DO J = 2, (Init%NDiv-1)
             knode = knode + 1
             Init%MemberNodes(I, J+1) = knode

             CALL SetNewNode(knode, x1 + J*dx, y1 + J*dy, z1 + J*dz, Init) ! Set Init%Nodes(knode,:)
             
             IF ( CreateNewProp ) THEN   
                  ! create a new property set 
                  ! k, E, G, rho, d, t, Init                
                  kprop = kprop + 1
                  CALL SetNewProp(kprop, TempProps(Prop1, 2), TempProps(Prop1, 3), Init%PropSetsB(Prop1, 4), d1 + J*dd, t1 + J*dt,  TempProps)           
                  kelem = kelem + 1
                  CALL SetNewElem(kelem, knode-1, knode, eType, nprop, kprop, p)
                  nprop = kprop
             ELSE
                  kelem = kelem + 1
                  CALL SetNewElem(kelem, knode-1, knode, eType, nprop, nprop, p)                          
             ENDIF
          ENDDO
          
          ! the element connect to Node2
          kelem = kelem + 1
          CALL SetNewElem(kelem, knode, Node2, eType, nprop, Prop2, p)                
       ENDDO ! loop over all members
       !
       Init%NPropB = kprop
       Init%NElem  = kelem ! TODO since not all members might have been divided
       Init%NNode  = knode ! TODO since not all members might have been divided

    ENDIF ! if NDiv is greater than 1

    ! set the props in Init
    CALL AllocAry(Init%PropsB, Init%NPropB, PropSetsBCol, 'Init%PropsBeams', ErrStat2, ErrMsg2); if(Failed()) return

    if (Init%NDiv==1) then
       Init%PropsB(1:Init%NPropB, 1:PropSetsBCol) = Init%PropSetsB(1:Init%NPropB, 1:PropSetsBCol)
    else if (Init%NDiv>1) then
       Init%PropsB(1:Init%NPropB, 1:PropSetsBCol) = TempProps(1:Init%NPropB, 1:PropSetsBCol)
    endif

    ! --- Cables and rigid link properties (these cannot be subdivided, so direct copy of inputs)
    Init%NPropC = Init%NPropSetsC
    Init%NPropR = Init%NPropSetsR
    CALL AllocAry(Init%PropsC, Init%NPropC, PropSetsCCol, 'Init%PropsCable', ErrStat2, ErrMsg2); if(Failed()) return
    CALL AllocAry(Init%PropsR, Init%NPropR, PropSetsRCol, 'Init%PropsRigid', ErrStat2, ErrMsg2); if(Failed()) return
    Init%PropsC(1:Init%NPropC, 1:PropSetsCCol) = Init%PropSetsC(1:Init%NPropC, 1:PropSetsCCol)
    Init%PropsR(1:Init%NPropR, 1:PropSetsRCol) = Init%PropSetsR(1:Init%NPropR, 1:PropSetsRCol)

    CALL CleanUp_Discrt()

CONTAINS
   LOGICAL FUNCTION Failed()
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'SD_Discrt') 
      Failed =  ErrStat >= AbortErrLev
      if (Failed) CALL CleanUp_Discrt()
   END FUNCTION Failed

   SUBROUTINE Fatal(ErrMsg_in)
      CHARACTER(len=*), intent(in) :: ErrMsg_in
      CALL SetErrStat(ErrID_Fatal, ErrMsg_in, ErrStat, ErrMsg, 'SD_Discrt');
      CALL CleanUp_Discrt()
   END SUBROUTINE Fatal

   SUBROUTINE CleanUp_Discrt()
      ! deallocate temp matrices
      IF (ALLOCATED(TempProps))   DEALLOCATE(TempProps)
      IF (ALLOCATED(TempMembers)) DEALLOCATE(TempMembers)
   END SUBROUTINE CleanUp_Discrt

   !> Set properties of node k
   SUBROUTINE SetNewNode(k, x, y, z, Init)
      TYPE(SD_InitType),      INTENT(INOUT) :: Init
      INTEGER,                INTENT(IN)    :: k
      REAL(ReKi),             INTENT(IN)    :: x, y, z
      Init%Nodes(k, 1)                     = k
      Init%Nodes(k, 2)                     = x
      Init%Nodes(k, 3)                     = y
      Init%Nodes(k, 4)                     = z
      Init%Nodes(k, iJointType)            = idJointCantilever ! Note: all added nodes are Cantilever
      ! Properties below are for non-cantilever joints
      Init%Nodes(k, iJointDir:iJointDir+2) = -99999 
      Init%Nodes(k, iJointStiff)           = -99999 
      Init%Nodes(k, iJointDamp)            = -99999 
   END SUBROUTINE SetNewNode
   
   !> Set properties of element k
   SUBROUTINE SetNewElem(k, n1, n2, etype, p1, p2, p)
      INTEGER,                INTENT(IN   )   :: k
      INTEGER,                INTENT(IN   )   :: n1
      INTEGER,                INTENT(IN   )   :: n2
      INTEGER,                INTENT(IN   )   :: eType
      INTEGER,                INTENT(IN   )   :: p1
      INTEGER,                INTENT(IN   )   :: p2
      TYPE(SD_ParameterType), INTENT(INOUT)   :: p
      p%Elems(k, 1)        = k
      p%Elems(k, 2)        = n1
      p%Elems(k, 3)        = n2
      p%Elems(k, iMProp  ) = p1
      p%Elems(k, iMProp+1) = p2
      p%Elems(k, iMType)   = eType
   END SUBROUTINE SetNewElem

   !> Set material properties of element k,  NOTE: this is only for a beam
   SUBROUTINE SetNewProp(k, E, G, rho, d, t, TempProps)
      INTEGER   , INTENT(IN)   :: k
      REAL(ReKi), INTENT(IN)   :: E, G, rho, d, t
      REAL(ReKi), INTENT(INOUT):: TempProps(:, :)
      TempProps(k, 1) = k
      TempProps(k, 2) = E
      TempProps(k, 3) = G
      TempProps(k, 4) = rho
      TempProps(k, 5) = d
      TempProps(k, 6) = t
   END SUBROUTINE SetNewProp

END SUBROUTINE SD_Discrt

!------------------------------------------------------------------------------------------------------
!> Set Element properties p%ElemProps, different properties are set depening on element type..
SUBROUTINE SetElementProperties(Init, p, ErrStat, ErrMsg)
   TYPE(SD_InitType),            INTENT(IN   ) :: Init
   TYPE(SD_ParameterType),       INTENT(INOUT) :: p
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   ! Local variables
   INTEGER                  :: I, J, K, iTmp
   INTEGER                  :: N1, N2     ! starting node and ending node in the element
   INTEGER                  :: P1, P2     ! property set numbers for starting and ending nodes
   REAL(ReKi)               :: D1, D2, t1, t2, E, G, rho ! properties of a section
   REAL(ReKi)               :: DirCos(3, 3)              ! direction cosine matrices
   REAL(ReKi)               :: L                         ! length of the element
   REAL(ReKi)               :: T0                        ! pretension force in cable [N]
   REAL(ReKi)               :: r1, r2, t, Iyy, Jzz, Ixx, A, kappa, nu, ratioSq, D_inner, D_outer
   LOGICAL                  :: shear
   INTEGER(IntKi)           :: eType !< Member type
   REAL(ReKi)               :: Point1(3), Point2(3) ! (x,y,z) positions of two nodes making up an element
   INTEGER(IntKi)           :: ErrStat2
   CHARACTER(ErrMsgLen)     :: ErrMsg2
   ErrMsg  = ""
   ErrStat = ErrID_None
   
   ALLOCATE( p%ElemProps(Init%NElem), STAT=ErrStat2); ErrMsg2='Error allocating p%ElemProps'
   if(Failed()) return
   
   ! Loop over all elements and set ElementProperties
   do I = 1, Init%NElem
      N1 = p%Elems(I, 2)
      N2 = p%Elems(I, 3)
      
      P1    = p%Elems(I, iMProp  )
      P2    = p%Elems(I, iMProp+1)
      eType = p%Elems(I, iMType)

      ! --- Properties common to all element types: L, DirCos (and Area and rho)
      Point1 = Init%Nodes(N1,2:4)
      Point2 = Init%Nodes(N2,2:4)
      CALL GetDirCos(Point1, Point2, DirCos, L, ErrStat2, ErrMsg2); if(Failed()) return ! L and DirCos
      p%ElemProps(i)%eType  = eType
      p%ElemProps(i)%Length = L
      p%ElemProps(i)%DirCos = DirCos

      ! Init to excessive values to detect any issue
      p%ElemProps(i)%Ixx     = -9.99e+36
      p%ElemProps(i)%Iyy     = -9.99e+36
      p%ElemProps(i)%Jzz     = -9.99e+36
      p%ElemProps(i)%Kappa   = -9.99e+36
      p%ElemProps(i)%YoungE  = -9.99e+36
      p%ElemProps(i)%ShearG  = -9.99e+36
      p%ElemProps(i)%Area    = -9.99e+36
      p%ElemProps(i)%Rho     = -9.99e+36
      p%ElemProps(i)%T0      = -9.99e+36

      ! --- Properties that are specific to some elements
      if (eType==idMemberBeam) then
         E   = Init%PropsB(P1, 2)
         G   = Init%PropsB(P1, 3)
         rho = Init%PropsB(P1, 4)
         D1  = Init%PropsB(P1, 5)
         t1  = Init%PropsB(P1, 6)
         D2  = Init%PropsB(P2, 5)
         t2  = Init%PropsB(P2, 6)
         r1 = 0.25*(D1 + D2)
         t  = 0.5*(t1+t2)
         if ( EqualRealNos(t, 0.0_ReKi) ) then
            r2 = 0
         else
            r2 = r1 - t
         endif
         A = Pi_D*(r1*r1-r2*r2)
         Ixx = 0.25*Pi_D*(r1**4-r2**4)
         Iyy = Ixx
         Jzz = 2.0*Ixx
         
         if( Init%FEMMod == 1 ) then ! uniform Euler-Bernoulli
            Shear = .false.
            kappa = 0
         elseif( Init%FEMMod == 3 ) then ! uniform Timoshenko
            Shear = .true.
          ! kappa = 0.53            
            ! equation 13 (Steinboeck et al) in SubDyn Theory Manual 
            nu = E / (2.0_ReKi*G) - 1.0_ReKi
            D_outer = 2.0_ReKi * r1  ! average (outer) diameter
            D_inner = D_outer - 2*t  ! remove 2x thickness to get inner diameter
            ratioSq = ( D_inner / D_outer)**2
            kappa =   ( 6.0 * (1.0 + nu) **2 * (1.0 + ratioSq)**2 ) &
                    / ( ( 1.0 + ratioSq )**2 * ( 7.0 + 14.0*nu + 8.0*nu**2 ) + 4.0 * ratioSq * ( 5.0 + 10.0*nu + 4.0 *nu**2 ) )
         endif
         ! Storing Beam specific properties
         p%ElemProps(i)%Ixx    = Ixx
         p%ElemProps(i)%Iyy    = Iyy
         p%ElemProps(i)%Jzz    = Jzz
         p%ElemProps(i)%Shear  = Shear
         p%ElemProps(i)%kappa  = kappa
         p%ElemProps(i)%YoungE = E
         p%ElemProps(i)%ShearG = G
         p%ElemProps(i)%Area   = A
         p%ElemProps(i)%Rho    = rho

      else if (eType==idMemberCable) then
         print*,'Member',I,'eType',eType,'Ps',P1,P2
         p%ElemProps(i)%Area   = 1                       ! Arbitrary set to 1
         p%ElemProps(i)%YoungE = Init%PropsC(P1, 2)/1    ! Young's modulus, E=EA/A  [N/m^2]
         p%ElemProps(i)%Rho    = Init%PropsC(P1, 3)      ! Material density [kg/m3]
         p%ElemProps(i)%T0     = Init%PropsC(P1, 4)      ! Pretension force [N]

      else if (eType==idMemberRigid) then
         print*,'Member',I,'eType',eType,'Ps',P1,P2
         p%ElemProps(i)%Area   = 1                  ! Arbitrary set to 1
         p%ElemProps(i)%Rho    = Init%PropsR(P1, 2)

      else
         ! Should not happen
         print*,'Element type unknown',eType
         STOP
      end if
   enddo ! I end loop over elements
CONTAINS
   LOGICAL FUNCTION Failed()
        call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'SetElementProperties') 
        Failed =  ErrStat >= AbortErrLev
   END FUNCTION Failed
END SUBROUTINE SetElementProperties 


!> Distribute global DOF indices corresponding to Nodes, Elements, BCs, Reactions
!! For Cantilever Joint -> Condensation into 3 translational and 3 rotational DOFs
!! For other joint type -> Condensation of the 3 translational DOF
!!                      -> Keeping 3 rotational DOF for each memeber connected to the joint
SUBROUTINE DistributeDOF(Init, p, m, ErrStat, ErrMsg)
   use IntegerList, only: init_list, len
   TYPE(SD_InitType),            INTENT(INOUT) :: Init
   TYPE(SD_ParameterType),       INTENT(IN   ) :: p
   TYPE(SD_MiscVarType),         INTENT(INOUT) :: m
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   integer(IntKi) :: iNode, k
   integer(IntKi) :: iPrev ! Cumulative counter over the global DOF
   integer(IntKi) :: iElem ! 
   integer(IntKi) :: idElem
   integer(IntKi) :: nRot ! Number of rotational DOFs (multiple of 3) to be used at the joint
   integer(IntKi) :: iOff ! Offset, 0 or 6, depending if node 1 or node 2
   integer(IntKi), dimension(6) :: DOFNode_Old
   integer(IntKi)           :: ErrStat2
   character(ErrMsgLen)     :: ErrMsg2
   ErrMsg  = ""
   ErrStat = ErrID_None

   allocate(m%NodesDOF(1:Init%NNode), stat=ErrStat2)
   ErrMsg2="Error allocating NodesDOF"
   if(Failed()) return

   call AllocAry(m%ElemsDOF, 12, Init%NElem, 'ElemsDOF', ErrStat2, ErrMsg2); if(Failed()) return;
   m%ElemsDOF=-9999

   iPrev =0
   do iNode = 1, Init%NNode
      ! --- Distribute to joints iPrev + 1:6, or, iPrev + 1:(3+3m)
      if (int(Init%Nodes(iNode,iJointType)) == idJointCantilever ) then
         nRot=3
      else
         nRot= 3*Init%NodesConnE(iNode,1) ! Col1: number of elements connected to this joint
      endif
      call init_list(m%NodesDOF(iNode), 3+nRot, iPrev, ErrStat2, ErrMsg2)
      m%NodesDOF(iNode)%List(1:(3+nRot)) = (/ ((iElem+iPrev), iElem=1,3+nRot) /)

      ! --- Distribute to members
      do iElem = 1, Init%NodesConnE(iNode,1) ! members connected to joint iJ
         idElem = Init%NodesConnE(iNode,iElem+1)
         if (iNode == p%Elems(idElem, 2)) then ! Current joint is Elem node 1
            iOff = 0
         else                              ! Current joint is Elem node 2
            iOff = 6
         endif
         m%ElemsDOF(iOff+1:iOff+3, idElem) =  m%NodesDOF(iNode)%List(1:3)
         if (int(Init%Nodes(iNode,iJointType)) == idJointCantilever ) then
            m%ElemsDOF(iOff+4:iOff+6, idElem) = m%NodesDOF(iNode)%List(4:6)
         else
            m%ElemsDOF(iOff+4:iOff+6, idElem) = m%NodesDOF(iNode)%List(3*iElem+1:3*iElem+3)   
         endif
      enddo ! iElem, loop on members connect to joint
      iPrev = iPrev + len(m%NodesDOF(iNode))
   enddo ! iNode, loop on joints

   ! --- Initialize boundary constraint vector - NOTE: Needs Reindexing first
   CALL AllocAry(Init%BCs, 6*p%NReact, 2, 'Init%BCs', ErrStat2, ErrMsg2); if(Failed()) return
   CALL InitBCs(Init, p)
      
   ! --- Initialize interface constraint vector - NOTE: Needs Reindexing first
   CALL AllocAry(Init%IntFc,      6*Init%NInterf,2,          'Init%IntFc',      ErrStat2, ErrMsg2); if(Failed()) return
   CALL InitIntFc(Init, p)

   ! --- Safety check
   if (any(m%ElemsDOF<0)) then
      ErrStat=ErrID_Fatal
      ErrMsg ="Implementation error in Distribute DOF, some member DOF were not allocated"
   endif

   ! --- Safety check (backward compatibility, only valid if all joints are Cantilever)
   if (Init%NNode == count( Init%Nodes(:, iJointType) == idJointCantilever)) then
      do idElem = 1, Init%NElem
         iNode = p%Elems(idElem, 2)
         DOFNode_Old= (/ ((iNode*6-5+k), k=0,5) /)
         if ( any( (m%ElemsDOF(1:6, idElem) /= DOFNode_Old)) ) then
            ErrStat=ErrID_Fatal
            ErrMsg ="Implementation error in Distribute DOF, DOF indices have changed for iElem="//trim(Num2LStr(idElem))
            return
         endif
      enddo
   else
      ! Safety check does not apply if some joints are non-cantilever
   endif

CONTAINS
   LOGICAL FUNCTION Failed()
        call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'SetElementProperties') 
        Failed =  ErrStat >= AbortErrLev
   END FUNCTION Failed

   !> Sets a list of DOF indices corresponding to the BC, and the value these DOF should have
   !! NOTE: need p%Reacts to have an updated first column that uses indices and not JointIDs
   SUBROUTINE InitBCs(Init, p)
      TYPE(SD_InitType     ),INTENT(INOUT) :: Init
      TYPE(SD_ParameterType),INTENT(IN   ) :: p
      INTEGER(IntKi) :: I, J, iNode
      Init%BCs = 0
      DO I = 1, p%NReact
         iNode = p%Reacts(I,1) ! Node index
         DO J = 1, 6
            Init%BCs( (I-1)*6+J, 1) = m%NodesDOF(iNode)%List(J)
            Init%BCs( (I-1)*6+J, 2) = p%Reacts(I, J+1);
         ENDDO
      ENDDO
   END SUBROUTINE InitBCs

   !> Sets a list of DOF indices and the value these DOF should have
   !! NOTE: need Init%Interf to have been reindexed so that first column uses indices and not JointIDs
   SUBROUTINE InitIntFc(Init, p)
      TYPE(SD_InitType     ),INTENT(INOUT) :: Init
      TYPE(SD_ParameterType),INTENT(IN   ) :: p
      INTEGER(IntKi) :: I, J, iNode
      Init%IntFc = 0
      DO I = 1, Init%NInterf
         iNode = Init%Interf(I,1) ! Node index
         DO J = 1, 6
            Init%IntFc( (I-1)*6+J, 1) = m%NodesDOF(iNode)%List(J)
            Init%IntFc( (I-1)*6+J, 2) = Init%Interf(I, J+1);
         ENDDO
      ENDDO
   END SUBROUTINE InitIntFc

END SUBROUTINE DistributeDOF

!------------------------------------------------------------------------------------------------------
!> Assemble stiffness and mass matrix, and gravity force vector
SUBROUTINE AssembleKM(Init, p, m, ErrStat, ErrMsg)
   TYPE(SD_InitType),            INTENT(INOUT) :: Init
   TYPE(SD_ParameterType),       INTENT(INOUT) :: p
   TYPE(SD_MiscVarType),         INTENT(INOUT) :: m
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   ! Local variables
   INTEGER                  :: I, J, K
   INTEGER                  :: iGlob
   REAL(ReKi)               :: Ke(12,12), Me(12, 12), FGe(12) ! element stiffness and mass matrices gravity force vector
   REAL(ReKi)               :: FCe(12) ! Pretension force from cable element
   INTEGER(IntKi)           :: ErrStat2
   CHARACTER(ErrMsgLen)     :: ErrMsg2
   INTEGER(IntKi)           :: iNode !< Node index
   integer(IntKi), dimension(12) :: IDOF !  12 DOF indices in global unconstrained system
   integer(IntKi), dimension(3)  :: IDOF3!  3  DOF indices in global unconstrained system
   ErrMsg  = ""
   ErrStat = ErrID_None
   
   ! total unconstrained degrees of freedom of the system 
   Init%TDOF = nDOF_Unconstrained()
   print*,'nDOF_unconstrained:',Init%TDOF, ' (if all Cantilever, it would be: ',6*Init%NNode,')'

   CALL AllocAry( Init%K, Init%TDOF, Init%TDOF , 'Init%K',  ErrStat2, ErrMsg2); if(Failed()) return; ! system stiffness matrix 
   CALL AllocAry( Init%M, Init%TDOF, Init%TDOF , 'Init%M',  ErrStat2, ErrMsg2); if(Failed()) return; ! system mass matrix 
   CALL AllocAry( Init%FG,Init%TDOF,             'Init%FG', ErrStat2, ErrMsg2); if(Failed()) return; ! system gravity force vector 
   Init%K  = 0.0_ReKi
   Init%M  = 0.0_ReKi
   Init%FG = 0.0_ReKi

   ! loop over all elements, compute element matrices and assemble into global matrices
   DO i = 1, Init%NElem
      ! --- Element Me,Ke,Fg, Fce
      CALL ElemM(p%ElemProps(i), Me)
      CALL ElemK(p%ElemProps(i), Ke)
      CALL ElemF(p%ElemProps(i), Init%g, FGe, FCe)

      ! --- Assembly in global unconstrained system
      IDOF = m%ElemsDOF(1:12, i)
      Init%FG( IDOF )    = Init%FG( IDOF )     + FGe(1:12)+ FCe(1:12) ! Note: gravity and pretension cable forces
      Init%K(IDOF, IDOF) = Init%K( IDOF, IDOF) + Ke(1:12,1:12)
      Init%M(IDOF, IDOF) = Init%M( IDOF, IDOF) + Me(1:12,1:12)
   ENDDO ! end loop over elements , i
      
   ! add concentrated mass 
   DO I = 1, Init%NCMass
      iNode = NINT(Init%CMass(I, 1)) ! Note index where concentrated mass is to be added
      ! Safety
      if (Init%Nodes(iNode,iJointType) /= idJointCantilever) then
         ErrMsg2='Concentrated mass is only for cantilever joints. Problematic node: '//trim(Num2LStr(iNode)); ErrStat2=ErrID_Fatal;
         if(Failed()) return
      endif
      DO J = 1, 3
          iGlob = m%NodesDOF(iNode)%List(J) ! ux, uy, uz
          Init%M(iGlob, iGlob) = Init%M(iGlob, iGlob) + Init%CMass(I, 2)
      ENDDO
      DO J = 4, 6
          iGlob = m%NodesDOF(iNode)%List(J) ! theta_x, theta_y, theta_z
          Init%M(iGlob, iGlob) = Init%M(iGlob, iGlob) + Init%CMass(I, J-1)
      ENDDO
   ENDDO ! Loop on concentrated mass

   ! add concentrated mass induced gravity force
   DO I = 1, Init%NCMass
       iGlob = m%NodesDOF(i)%List(3) ! uz
       Init%FG(iGlob) = Init%FG(iGlob) - Init%CMass(I, 2)*Init%g 
   ENDDO ! I concentrated mass induced gravity
   
   CALL CleanUp_AssembleKM()
   
CONTAINS
   LOGICAL FUNCTION Failed()
        call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'AssembleKM') 
        Failed =  ErrStat >= AbortErrLev
        if (Failed) call Cleanup_AssembleKM()
   END FUNCTION Failed
   
   SUBROUTINE Fatal(ErrMsg_in)
      character(len=*), intent(in) :: ErrMsg_in
      CALL SetErrStat(ErrID_Fatal, ErrMsg_in, ErrStat, ErrMsg, 'AssembleKM');
      CALL CleanUp_AssembleKM()
   END SUBROUTINE Fatal

   SUBROUTINE CleanUp_AssembleKM()
      !pass
   END SUBROUTINE CleanUp_AssembleKM

   INTEGER(IntKi) FUNCTION nDOF_Unconstrained()
      integer(IntKi) :: i
      integer(IntKi) :: m
      nDOF_Unconstrained=0
      do i = 1,Init%NNode
         if (int(Init%Nodes(i,iJointType)) == idJointCantilever ) then
            nDOF_Unconstrained = nDOF_Unconstrained + 6
         else
            m = Init%NodesConnE(i,1) ! Col1: number of elements connected to this joint
            nDOF_Unconstrained = nDOF_Unconstrained + 3 + 3*m
         endif
      end do
   END FUNCTION
   
END SUBROUTINE AssembleKM

!------------------------------------------------------------------------------------------------------
!> Build transformation matrix T, such that x= T.x~ where x~ is the reduced vector of DOF
SUBROUTINE BuildTMatrix(Init, p, RA, RAm1, m, Tred, ErrStat, ErrMsg)
   use IntegerList, only: init_list, find, pop, destroy_list, len
   use IntegerList, only: print_list
   TYPE(SD_InitType),            INTENT(IN   ) :: Init
   TYPE(SD_ParameterType),       INTENT(IN   ) :: p
   type(IList), dimension(:),    INTENT(IN   ) :: RA   !< RA(a) = [e1,..,en]  list of elements forming a rigid link assembly
   integer(IntKi), dimension(:), INTENT(IN   ) :: RAm1 !< RA^-1(e) = a , for a given element give the index of a rigid assembly
   TYPE(SD_MiscVarType),target,  INTENT(INOUT) :: m
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   real(ReKi), dimension(:,:), allocatable :: Tred !< Transformation matrix for DOF elimination
   ! Local  
   real(ReKi), dimension(:,:), allocatable   :: Tc
   integer(IntKi), dimension(:), allocatable :: INodesID !< List of unique nodes involved in Elements
   integer(IntKi), dimension(:), allocatable :: IDOFOld !< 
   integer(IntKi), dimension(:), pointer :: IDOFNew !< 
   real(ReKi), dimension(6,6) :: I6       !< Identity matrix of size 6
   integer(IntKi) :: iPrev
   type(IList) :: IRA !< list of rigid assembly indices to process
   integer(IntKi) :: nDOF
   integer(IntKi) :: aID, ia ! assembly ID, and index in IRA
   integer(IntKi) :: iNode
   integer(IntKi) :: JType
   integer(IntKi) :: I
   integer(IntKi) :: nc !< Number of DOF after constraints applied
   integer(IntKi) :: nj
   real(ReKi)  :: phat(3) !< Directional vector of the joint
   INTEGER(IntKi)       :: ErrStat2
   CHARACTER(ErrMsgLen) :: ErrMsg2
   ErrStat = ErrID_None
   ErrMsg  = ""

   ! --- Misc inits
   nullify(IDOFNew)
   I6(1:6,1:6)=0; do i = 1,6 ; I6(i,i)=1_ReKi; enddo ! I6 =  eye(6)
   allocate(m%NodesDOFtilde(1:Init%NNode), stat=ErrStat2); if(Failed()) return; ! Indices of DOF for each joint, in reduced system

   nDOF = nDOF_ConstraintReduced()
   print*,'nDOF constraint elim', nDOF , '/' , Init%TDOF
   CALL AllocAry( m%Tred, Init%TDOF, nDOF, 'm%Tred',  ErrStat2, ErrMsg2); if(Failed()) return; ! system stiffness matrix 
   Tred=0
   call init_list(IRA, size(RA), 0, ErrStat2, ErrMsg2); if(Failed()) return;
   IRA%List(1:size(RA)) = (/(ia , ia = 1,size(RA))/)
   call print_list(IRA, 'List of RA indices')

   ! --- For each node:
   !  - create list of indices I      in the assembled vector of DOF
   !  - create list of indices Itilde in the reduced vector of DOF
   !  - increment iPrev by the number of DOF of Itilde
   iPrev =0 
   do iNode = 1, Init%NNode
      if (allocated(Tc)) deallocate(Tc)
      if (allocated(IDOFOld)) deallocate(IDOFOld)
      JType = int(Init%Nodes(iNode,iJointType))
      if(JType == idJointCantilever ) then
         if ( NodeHasRigidElem(iNode, Init, p)) then
            ! --- Joint involved in a rigid link assembly
            aID = RAm1(iNode)
            ia  = find(IRA, aID, ErrStat2, ErrMsg2) 
            print*,'Node',iNode, 'is involved in RA', aID, ia
            if ( ia <= 0) then
               ! This rigid assembly has already been processed, pass to next node
               cycle
            else
               call RAElimination( RA(aID)%List, Tc, INodesID, Init, p, ErrStat2, ErrMsg2); if(Failed()) return;
               aID = pop(IRA, ia, ErrStat2, ErrMsg2) ! this assembly has been processed 
               nj = size(INodesID)
               allocate(IDOFOld(1:6*nj))
               do I=1, nj
                  IDOFOld( (I-1)*6+1 : I*6 ) = m%NodesDOF(INodesID(I))%List(1:6)
               enddo
            endif
         else
            ! --- Regular cantilever joint
            allocate(Tc(1:6,1:6))
            allocate(IDOFOld(1:6))
            Tc=I6
            IDOFOld = m%NodesDOF(iNode)%List(1:6)
         endif
      else
         ! --- Ball/Pin/Universal joint
         allocate(IDOFOld(1:len(m%NodesDOF(iNode))))
         IDOFOld(:) = m%NodesDOF(iNode)%List(:)
         phat = Init%Nodes(iNode, iJointDir:iJointDir+2)
         call JointElimination(Init%NodesConnE(iNode,:), JType, phat, Init, p, Tc, ErrStat2, ErrMsg2); if(Failed()) return
      endif
      nc=size(Tc,2) 
      call init_list(m%NodesDOFtilde(iNode), nc, 0, ErrStat2, ErrMsg2)
      m%NodesDOFtilde(iNode)%List(1:nc) = (/ (iprev + i, i=1,nc) /)
      IDOFNew => m%NodesDOFtilde(iNode)%List(1:nc) ! alias to shorten notations
      print*,'N',iNode,'I ',IDOFOld
      print*,'N',iNode,'It',IDOFNew
      Tred(IDOFOld, IDOFNew) = Tc
      iPrev = iPrev + nc
   enddo
   ! --- Safety checks
   if (len(IRA)>0) then 
      ErrMsg2='Not all rigid assemblies were processed'; ErrStat2=ErrID_Fatal
      if(Failed()) return
   endif
   if (iPrev /= nDOF) then 
      ErrMsg2='Inconsistency in number of reduced DOF'; ErrStat2=ErrID_Fatal
      if(Failed()) return
   endif
   call CleanUp_BuildTMatrix()
contains
   LOGICAL FUNCTION Failed()
      call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'BuildTMatrix') 
      Failed =  ErrStat >= AbortErrLev
      if (Failed) call CleanUp_BuildTMatrix()
   END FUNCTION Failed

   SUBROUTINE CleanUp_BuildTMatrix()
      nullify(IDOFNew)
      call destroy_list(IRA, ErrStat2, ErrMsg2)
      if (allocated(Tc)     ) deallocate(Tc)
      if (allocated(IDOFOld)) deallocate(IDOFOld)
      if (allocated(INodesID)) deallocate(INodesID)
   END SUBROUTINE CleanUp_BuildTMatrix

   !> Returns number of DOF after constraint reduction (via the matrix T)
   INTEGER(IntKi) FUNCTION nDOF_ConstraintReduced()
      integer(IntKi) :: iNode
      integer(IntKi) :: ia ! Index on rigid link assembly
      integer(IntKi) :: m  ! Number of elements connected to a joint
      integer(IntKi) :: NodeType
      nDOF_ConstraintReduced = 0

      ! Rigid assemblies contribution
      nDOF_ConstraintReduced = nDOF_ConstraintReduced + 6*size(RA)

      ! Contribution from all the other joints
      do iNode = 1, Init%NNode
         m = Init%NodesConnE(iNode,1) ! Col1: number of elements connected to this joint
         NodeType = Init%Nodes(iNode,iJointType)

         if    (NodeType == idJointPin ) then
            nDOF_ConstraintReduced = nDOF_ConstraintReduced + 5 + 1*m
            print*,'Node',iNode, 'is a pin joint, number of members involved: ', m

         elseif(NodeType == idJointUniversal ) then
            nDOF_ConstraintReduced = nDOF_ConstraintReduced + 4 + 2*m
            print*,'Node',iNode, 'is an universal joint, number of members involved: ', m

         elseif(NodeType == idJointBall ) then
            nDOF_ConstraintReduced = nDOF_ConstraintReduced + 3 + 3*m
            print*,'Node',iNode, 'is a ball joint, number of members involved: ', m

         elseif(NodeType == idJointCantilever ) then
            if ( NodeHasRigidElem(iNode, Init, p)) then
               ! This joint is involved in a rigid link assembly, we skip it (accounted for above)
               print*,'Node',iNode, 'is involved in a RA'
            else
               ! That's a regular Cantilever joint
               nDOF_ConstraintReduced = nDOF_ConstraintReduced + 6
               !print*,'Node',iNode, 'is a regular cantilever'
            endif
         else
            ErrMsg='Wrong joint type'; ErrStat=ErrID_Fatal
         endif
      end do
   END FUNCTION nDOF_ConstraintReduced
END SUBROUTINE BuildTMatrix
!------------------------------------------------------------------------------------------------------
!> Assemble stiffness and mass matrix, and gravity force vector
SUBROUTINE DirectElimination(Init, p, m, ErrStat, ErrMsg)
   TYPE(SD_InitType),            INTENT(INOUT) :: Init
   TYPE(SD_ParameterType),       INTENT(INOUT) :: p
   TYPE(SD_MiscVarType),target,  INTENT(INOUT) :: m
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   ! Local variables
   INTEGER(IntKi)                            :: ErrStat2
   CHARACTER(ErrMsgLen)                      :: ErrMsg2
   ! Varaibles for rigid assembly
   type(IList), dimension(:), allocatable    :: RA       !< RA(a) = [e1,..,en]  list of elements forming a rigid link assembly
   integer(IntKi), dimension(:), allocatable :: RAm1 !< RA^-1(e) = a , for a given element give the index of a rigid assembly
   real(ReKi), dimension(:,:), allocatable :: MM, KK
   real(ReKi), dimension(:),   allocatable :: FF
   integer(IntKi) :: nDOF
   ErrStat = ErrID_None
   ErrMsg  = ""

   call RigidLinkAssemblies(Init, p, RA, RAm1, ErrStat2, ErrMsg2); if(Failed()) return

   call BuildTMatrix(Init, p, RA, RAm1, m, m%Tred, ErrStat2, ErrMsg2); if (Failed()) return

   ! --- DOF elimination for system matrices and RHS vector
   ! Temporary backup of M and K of full system
   call move_alloc(Init%M,  MM)
   call move_alloc(Init%K,  KK)
   call move_alloc(Init%FG, FF)
   !  Reallocating
   nDOF = size(m%Tred,2)
   CALL AllocAry( Init%D, nDOF, nDOF, 'Init%D',  ErrStat2, ErrMsg2); if(Failed()) return; ! system damping matrix 
   CALL AllocAry( Init%K, nDOF, nDOF, 'Init%K',  ErrStat2, ErrMsg2); if(Failed()) return; ! system stiffness matrix 
   CALL AllocAry( Init%M, nDOF, nDOF, 'Init%M',  ErrStat2, ErrMsg2); if(Failed()) return; ! system mass matrix 
   CALL AllocAry( Init%FG,nDOF,       'Init%FG', ErrStat2, ErrMsg2); if(Failed()) return; ! system gravity force vector 
   ! Elimination
   Init%M  = matmul(transpose(m%Tred), matmul(MM, m%Tred))
   Init%K  = matmul(transpose(m%Tred), matmul(KK, m%Tred))
   Init%FG = matmul(transpose(m%Tred), FF)
   Init%D = 0 !< Used for additional stiffness

   call CleanUp_DirectElimination()

CONTAINS
   LOGICAL FUNCTION Failed()
        call SetErrStat(ErrStat2, ErrMsg2, ErrStat, ErrMsg, 'DirectElimination') 
        Failed =  ErrStat >= AbortErrLev
        if (Failed) call CleanUp_DirectElimination()
   END FUNCTION Failed
   SUBROUTINE CleanUp_DirectElimination()
      ! Cleaning up memory
      if (allocated(MM  )) deallocate(MM  )
      if (allocated(KK  )) deallocate(KK  )
      if (allocated(FF  )) deallocate(FF  )
      if (allocated(RA  )) deallocate(RA  )
      if (allocated(RAm1)) deallocate(RAm1)
      if (allocated(RA  )) deallocate(RA  )
   END SUBROUTINE CleanUp_DirectElimination
END SUBROUTINE DirectElimination

!------------------------------------------------------------------------------------------------------
!> Returns constraint matrix Tc for a rigid assembly (RA) formed by a set of elements. 
!!   x_c = Tc.x_c_tilde  
!! where x_c are all the DOF of the rigid assembly, and x_c_tilde are the 6 reduced DOF (leader DOF)
SUBROUTINE RAElimination(Elements, Tc, INodesID, Init, p, ErrStat, ErrMsg)
   use IntegerList, only: init_list, len, append, print_list, pop, destroy_list, get
   integer(IntKi), dimension(:), INTENT(IN   ) :: Elements !< List of elements
   real(ReKi), dimension(:,:), allocatable     :: Tc
   integer(IntKi), dimension(:), allocatable   :: INodesID !< List of unique nodes involved in Elements
   TYPE(SD_InitType),            INTENT(IN   ) :: Init
   TYPE(SD_ParameterType),       INTENT(IN   ) :: p
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat  !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg   !< Error message if ErrStat /= ErrID_None
   ! Local variables
   type(IList)          :: LNodesID     !< List of nodes id involved in element
   type(IList)          :: INodesInterf !< List of indices for Nodes involved in interface
   integer(IntKi)       :: NodeID   !< NodeID
   integer(IntKi)       :: iTmp     !< Temporary index
   integer(IntKi)       :: iNodeID  !< Loop index on node ID list
   integer(IntKi)       :: iMainNode !< Index of main node selected for rigid assembly within INodesID list
   integer(IntKi)       :: nNodes  !< Number of Nodes involved in RA
   integer(IntKi)       :: iFound  !< Loop index on node ID list
   integer(IntKi)       :: i       !< Loop index 
   real(ReKi)           :: TRigid(6,6) ! Transformation matrix such that xi = T.x1
   real(ReKi)           :: P1(3), Pi(3) ! Nodal points
   INTEGER(IntKi)       :: ErrStat2
   CHARACTER(ErrMsgLen) :: ErrMsg2
   ErrStat = ErrID_None
   ErrMsg  = ""

   ! --- List of nodes stored first in LINodes than moved to INodes
   LNodesID = NodesList(p, Elements)
   if (allocated(INodesID)) deallocate(INodesID)
   call move_alloc(LNodesID%List, INodesID)
   call destroy_list(LNodesID, ErrStat2, ErrMsg2)
   print*,'Nodes involved in assembly (befr) ',INodesID

   !--- Look for potential interface node
   call init_list(INodesInterf, 0, 0, ErrStat2, ErrMsg2);
   do iNodeID = 1, size(INodesID)
      NodeID = INodesID(iNodeID)
      iFound =  FINDLOCI( Init%Interf(:,1), NodeID)
      if (iFound>0) then
         call append(INodesInterf, iNodeID, ErrStat2, ErrMsg2)
         ! This node is an interface node
         print*,'Node',NodeID, 'is an interface node, selecting it for the rigid assembly'
      endif
   enddo

   ! --- Decide which node will be the main node of the rigid assembly
   if      (len(INodesInterf)==0) then
      iMainNode = 1 ! By default we select the first node
   else if (len(INodesInterf)==1) then
      iMainNode = pop(INodesInterf, ErrStat2, ErrMsg2)
   else
      ErrStat=ErrID_Fatal
      ErrMsg='Cannot have several interface nodes linked within a same rigid assembly'
      return
   endif
   call destroy_list(INodesInterf, ErrStat2, ErrMsg2)

   ! --- Order list of joints with main node first (swapping iMainNode with INodes(1))
   iTmp                = INodesID(1)
   INodesID(1)         = iMainNode
   INodesID(iMainNode) = iTmp
   print*,'Nodes involved in assembly (after)',INodesID

   ! --- Building Transformation matrix
   nNodes =size(INodesID)
   allocate(Tc(6*nNodes,6))
   Tc(:,:)=0
   ! I6 for first node
   do i = 1,6 ; Tc(i,i)=1_ReKi; enddo ! I6 =  eye(6)
   ! Rigid transformation matrix for the other nodes 
   P1 = Init%Nodes(INodesID(1), 2:4) ! reference node coordinates
   do i = 2, nNodes
      Pi = Init%Nodes(INodesID(i), 2:4) ! follower node coordinates
      call GetRigidTransformation(P1, Pi, TRigid, ErrStat2, ErrMsg2)
      Tc( ((i-1)*6)+1:6*i, 1:6) = TRigid(1:6,1:6)
   enddo
END SUBROUTINE RAElimination
!------------------------------------------------------------------------------------------------------
!> Returns constraint matrix Tc for a joint involving several Elements
!!   x_c = Tc.x_c_tilde  
!! where
!    x_c       are all the DOF of the joint (3 translation + 3*m, m the number of elements) 
!    x_c_tilde are the nc reduced DOF 
SUBROUTINE JointElimination(Elements, JType, phat, Init, p, Tc, ErrStat, ErrMsg)
   use IntegerList, only: init_list, len, append, print_list, pop, destroy_list, get
   integer(IntKi), dimension(:), INTENT(IN   ) :: Elements !< List of elements involved at a joint
   integer(IntKi),               INTENT(IN   ) :: JType !< Joint type
   real(ReKi),                   INTENT(IN   ) :: phat(3) !< Directional vector of the joint
   TYPE(SD_InitType),            INTENT(IN   ) :: Init
   TYPE(SD_ParameterType),       INTENT(IN   ) :: p
   real(ReKi), dimension(:,:), allocatable     :: Tc  !< Transformation matrix from eliminated to full
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat  !< Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg   !< Error message if ErrStat /= ErrID_None
   ! Local variables
   !type(IList)          :: I !< List of indices for Nodes involved in interface
   integer(IntKi)       :: i, j, ie, ne       !< Loop index 
   integer(IntKi)       :: nDOFr     !< Number of reduced DOF
   integer(IntKi)       :: nDOFt     !< Number of total DOF *nreduced)
   real(ReKi)           :: e1(3), e2(3), e3(3) ! forming orthonormal basis with phat 
   integer(IntKi)       :: ErrStat2
   character(ErrMsgLen) :: ErrMsg2
   real(LaKi), dimension(:,:), allocatable :: Tc_rot !< Part of Tc just for rotational DOF
   real(LaKi), dimension(:,:), allocatable :: Tc_rot_m1 !< Inverse of Tc_rot
   real(ReKi) :: ColMean
   ErrStat = ErrID_None
   ErrMsg  = ""

   ne = Elements(1) ! TODO TODO
   nDOFt = 3 + 3*ne

   ! The elements already share the same translational DOF

   if    (JType == idJointPin ) then
      nDOFr = 5 + 1*ne
      allocate(Tc  (nDOFt, nDOFr)); 
      allocate(Tc_rot_m1(nDOFr-3, nDOFt-3)); 
      Tc(:,:)=0
      Tc_rot_m1(:,:)=0

      ! Normalizing 
      e3= phat/sqrt(phat(1)**2 + phat(2)**2 + phat(3)**2)
      call GetOrthVectors(e3, e1, e2, ErrStat2, ErrMsg2);
      ! Forming Tcm1, inverse of Tc
      do ie=1,ne
         Tc_rot_m1(1   , (ie-1)*3+1:ie*3 ) = e1(1:3)/ne
         Tc_rot_m1(2   , (ie-1)*3+1:ie*3 ) = e2(1:3)/ne
         Tc_rot_m1(ie+2, (ie-1)*3+1:ie*3 ) = e3(1:3)
      enddo
      ! Pseudo inverse:
      call PseudoInverse(Tc_rot_m1, Tc_rot, ErrStat2, ErrMsg2)
      ! --- Forming Tc
      do i = 1,3    ; Tc(i,i)=1_ReKi; enddo !  I3 for translational DOF
      Tc(4:nDOFt,4:nDOFr)=Tc_rot(1:nDOFt-3, 1:nDOFr-3)
      deallocate(Tc_rot)
      deallocate(Tc_rot_m1)

   elseif(JType == idJointUniversal ) then
      if (ne/=2) then
         ErrMsg='JointElimination: universal joints should only connect two elements.'; ErrStat=ErrID_Fatal
         return
      endif
      nDOFr = 4 + 2*ne
      allocate(Tc(nDOFt, nDOFr)); 
      allocate(Tc_rot_m1(nDOFr-3, nDOFt-3)); 
      Tc(:,:)=0
      Tc_rot_m1(:,:)=0 ! Important init
      ! Forming the inverse of Tc_rot
      Tc_rot_m1(1,1:3) = p%ElemProps(Elements(1))%DirCos(:,3)/2._ReKi
      Tc_rot_m1(1,4:6) = p%ElemProps(Elements(2))%DirCos(:,3)/2._ReKi
      Tc_rot_m1(2,1:3) = p%ElemProps(Elements(1))%DirCos(:,1)
      Tc_rot_m1(3,1:3) = p%ElemProps(Elements(1))%DirCos(:,2)
      Tc_rot_m1(4,4:6) = p%ElemProps(Elements(2))%DirCos(:,1)
      Tc_rot_m1(5,4:6) = p%ElemProps(Elements(2))%DirCos(:,2)
      ! Pseudo inverse
      call PseudoInverse(Tc_rot_m1, Tc_rot, ErrStat2, ErrMsg2)
      ! --- Forming Tc
      do i = 1,3    ; Tc(i,i)=1_ReKi; enddo !  I3 for translational DOF
      Tc(4:nDOFt,4:nDOFr)=Tc_rot(1:nDOFt-3, 1:nDOFr-3)
      deallocate(Tc_rot)
      deallocate(Tc_rot_m1)

   elseif(JType == idJointBall      ) then
      nDOFr = 3 + 3*ne
      allocate(Tc(nDOFt, nDOFr)); 
      Tc(:,:)=0
      do i = 1,3    ; Tc(i,i)=1_ReKi; enddo !  I3 for translational DOF
      do i = 3,nDOFr; Tc(i,i)=1_ReKi; enddo ! Identity for other DOF as well

   else
      ErrMsg='JointElimination: Wrong joint type'; ErrStat=ErrID_Fatal
   endif
   !do i=1,nDOFt
   !   print*,'Tc',Tc(i,:)
   !enddo
   STOP
   ! --- Safety check
   do j =1, size(Tc,2)
      ColMean=0; do i=1,size(Tc,1) ; ColMean = ColMean + abs(Tc(i,j)); enddo
      ColMean = ColMean/size(Tc,1)
      if (ColMean<1e-6) then
         ErrMsg='JointElimination: a reduced degree of freedom has a singular mapping.'; ErrStat=ErrID_Fatal
         return
      endif
   enddo

END SUBROUTINE JointElimination

!------------------------------------------------------------------------------------------------------
!> Setup a list of rigid link assemblies (RA)
SUBROUTINE RigidLinkAssemblies(Init, p, RA, RAm1, ErrStat, ErrMsg)
   use IntegerList, only: init_list, len, append, print_list, pop, destroy_list, get
   TYPE(SD_InitType),            INTENT(INOUT) :: Init
   TYPE(SD_ParameterType),       INTENT(INOUT) :: p
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   type(IList), dimension(:), allocatable    :: RA   !< RA(a) = [e1,..,en]  list of elements forming a rigid link assembly
   integer(IntKi), dimension(:), allocatable :: RAm1 !< RA^-1(e) = a , for a given element give the index of a rigid assembly
   ! Local variables
   type(IList)                               :: Er    !< List of rigid elements
   type(IList)                               :: Ea    !< List of elements in a rigid assembly
   integer(IntKi)                            :: nRA  !< Number of rigid assemblies
   integer(IntKi)                            :: ie  !< Index on elements
   integer(IntKi)                            :: ia  !< Index on assemblies
   integer(IntKi)                            :: e0  !< Index of an element
   INTEGER(IntKi)       :: ErrStat2
   CHARACTER(ErrMsgLen) :: ErrMsg2
   ErrStat = ErrID_None
   ErrMsg  = ""
   allocate(RAm1(1:Init%NElem))
   RAm1(1:Init%NElem) = -1

   ! --- Establish a list of rigid link elements
   Er = RigidLinkElements(Init, p, ErrStat2, ErrMsg2)
   nRA=0
   do while (len(Er)>0)
      nRA=nRA+1
      ! Creating List Ea of elements of a given assembly
      call init_list(Ea, 0, 0, ErrStat2, ErrMsg2);
      e0 = pop(Er, ErrStat2, ErrMsg2);
      call append(Ea, e0, ErrStat2, ErrMsg2);
      call AddNeighbors(e0, Er, Ea)
      call print_list(Ea,'Rigid assembly')
      do ie = 1, len(Ea)
         e0 = get(Ea, ie, ErrStat2, ErrMsg2)
         RAm1(e0) = nRA ! Index of rigid assembly that this element belongs to
      enddo
      call destroy_list(Ea, ErrStat2, ErrMsg2)
   enddo
   call destroy_list(Er, ErrStat2, ErrMsg2)

   ! --- Creating RA, array of lists of assembly elements.
   ! Note: exactly the same as all the Ea created above, but we didn't know the total number of RA
   allocate(RA(1:nRA))
   do ia = 1, nRA
      call init_list(RA(ia), 0, 0, ErrStat2, ErrMsg2)
   enddo
   do ie = 1, Init%NElem
      ia = RAm1(ie) ! Index of the assembly the element belongs to: RA^{-1}(ie) = ia
      if (ia>0) then
         call append(RA(ia), ie, ErrStat2, ErrMsg2)
      endif
   enddo
   do ia = 1, nRA
      call print_list(RA(ia),'Rigid assembly')
   enddo
CONTAINS
   !> The neighbors of e0 (that are found within the list Er) are added to the list Ea  
   RECURSIVE SUBROUTINE AddNeighbors(e0, Er, Ea) 
      integer(IntKi), intent(in) :: e0  !< Index of an element
      type(IList), intent(inout) :: Er  !< List of rigid elements
      type(IList), intent(inout) :: Ea  !< List of elements in a rigid assembly
      type(IList)     :: En             !< List of neighbors of e0
      integer (IntKi) :: ik
      integer (IntKi) :: ek, ek2
      integer (IntKi) :: iWhichNode_e0, iWhichNode_ek
      call init_list(En, 0, 0, ErrStat2, ErrMsg2)
      ! Loop through all elements, setup list of e0-neighbors, add them to Ea, remove them from Er
      ik=0
      do while (ik< len(Er))
         ik=ik+1
         ek = Er%List(ik)
         if (ElementsConnected(p, e0, ek, iWhichNode_e0, iWhichNode_ek)) then
            print*,'Element ',ek,'is connected to ',e0,'via its node',iWhichNode_ek
            ! Remove element from Er (a rigid element can belong to only one assembly)
            ek2 =  pop(Er, ik,  ErrStat2, ErrMsg2) ! same as ek before
            ik=ik-1
            if (ek/=ek2) then
               print*,'Problem in popping',ek,ek2
            endif
            call append(En, ek, ErrStat2, ErrMsg2)
            call append(Ea, ek, ErrStat2, ErrMsg2)
         endif
      enddo
      ! Loop through neighbors and recursively add neighbors of neighbors
      do ik = 1, len(En)
         ek = En%List(ik)
         call AddNeighbors(ek, Er, Ea)
      enddo
      call destroy_list(En, ErrStat2, ErrMsg2)
   END SUBROUTINE AddNeighbors


END SUBROUTINE RigidLinkAssemblies


!------------------------------------------------------------------------------------------------------
!> Add stiffness and damping to some joints
SUBROUTINE InsertJointStiffDamp(p, m, Init, ErrStat, ErrMsg)
   TYPE(SD_ParameterType),       INTENT(IN   ) :: p
   TYPE(SD_MiscVarType),target,  INTENT(IN   ) :: m
   TYPE(SD_InitType),            INTENT(INOUT) :: Init
   INTEGER(IntKi),               INTENT(  OUT) :: ErrStat     ! Error status of the operation
   CHARACTER(*),                 INTENT(  OUT) :: ErrMsg      ! Error message if ErrStat /= ErrID_None
   ! Local variables
   integer(IntKi) :: iNode, JType, iStart
   real(ReKi) :: StifAdd, DampAdd
   integer(IntKi), dimension(:), pointer :: Ifreerot
   ErrStat = ErrID_None
   ErrMsg  = ""
   do iNode = 1, Init%NNode
      JType   = int(Init%Nodes(iNode,iJointType))
      StifAdd = Init%Nodes(iNode, iJointStiff)
      DampAdd = Init%Nodes(iNode, iJointDamp )
      if(JType == idJointCantilever ) then
         ! Cantilever joints should not have damping or stiffness
         if(StifAdd>0) then 
            ErrMsg='InsertJointStiffDamp: Additional stiffness should be 0 for cantilever joints. Index of problematic node: '//trim(Num2LStr(iNode)); ErrStat=ErrID_Fatal;
            return
         endif
         if(DampAdd>0) then 
            ErrMsg='InsertJointStiffDamp: Additional damping should be 0 for cantilever joints. Index of problematic node: '//trim(Num2LStr(iNode)); ErrStat=ErrID_Fatal;
            return
         endif
      else
         ! Ball/Univ/Pin joints have damping/stiffness inserted at indices of "free rotation"
         if      ( JType == idJointBall      ) then; iStart=4;
         else if ( JType == idJointUniversal ) then; iStart=5;
         else if ( JType == idJointPin       ) then; iStart=6;
         endif
         Ifreerot=>m%NodesDOFtilde(iNode)%List(iStart:)
         ! Ball/Pin/Universal joints
         if(StifAdd>0) then 
            print*,'StiffAdd, Node',iNode,StifAdd, Ifreerot
            Init%K(Ifreerot,Ifreerot) = Init%K(Ifreerot,Ifreerot) + StifAdd
         endif
         if(DampAdd>0) then 
            print*,'DampAdd, Node',iNode,DampAdd, Ifreerot
            Init%D(Ifreerot,Ifreerot) = Init%D(Ifreerot,Ifreerot) +DampAdd
         endif
      endif
   enddo
END SUBROUTINE InsertJointStiffDamp

!> Apply constraint (Boundary conditions) on Mass and Stiffness matrices
SUBROUTINE ApplyConstr(Init,p)
   TYPE(SD_InitType     ),INTENT(INOUT):: Init
   TYPE(SD_ParameterType),INTENT(IN   ):: p
   
   INTEGER :: I !, J, k
   INTEGER :: row_n !bgn_j, end_j,
   
   DO I = 1, p%NReact*6
      row_n = Init%BCs(I, 1)
      IF (Init%BCs(I, 2) == 1) THEN
         Init%K(row_n,:    )= 0
         Init%K(:    ,row_n)= 0
         Init%K(row_n,row_n)= 1

         Init%M(row_n,:    )= 0
         Init%M(:    ,row_n)= 0
         Init%M(row_n,row_n)= 0
      ENDIF
   ENDDO ! I, loop on reaction nodes
END SUBROUTINE ApplyConstr


SUBROUTINE ElemM(ep, Me)
   TYPE(ElemPropType), INTENT(IN) :: eP        !< Element Property
   REAL(ReKi), INTENT(OUT)        :: Me(12, 12)
   if (ep%eType==idMemberBeam) then
      !Calculate Ke, Me to be used for output
      CALL ElemM_Beam(eP%Area, eP%Length, eP%Ixx, eP%Iyy, eP%Jzz,  eP%rho, eP%DirCos, Me)

   else if (ep%eType==idMemberCable) then
      CALL ElemM_Cable(ep%Area, ep%Length, ep%rho, ep%DirCos, Me)

   else if (ep%eType==idMemberRigid) then
      if ( EqualRealNos(eP%rho, 0.0_ReKi) ) then
         Me=0.0_ReKi
      else
         print*,'FEM: Mass matrix for rigid members rho/=0 TODO'
         CALL ElemM_Cable(ep%Area, ep%Length, ep%rho, ep%DirCos, Me)
         !CALL ElemM_(A, L, rho, DirCos, Me)
      endif
   endif
END SUBROUTINE ElemM

SUBROUTINE ElemK(ep, Ke)
   TYPE(ElemPropType), INTENT(IN) :: eP        !< Element Property
   REAL(ReKi), INTENT(OUT)        :: Ke(12, 12)

   if (ep%eType==idMemberBeam) then
      CALL ElemK_Beam( eP%Area, eP%Length, eP%Ixx, eP%Iyy, eP%Jzz, eP%Shear, eP%kappa, eP%YoungE, eP%ShearG, eP%DirCos, Ke)

   else if (ep%eType==idMemberCable) then
      CALL ElemK_Cable(ep%Area, ep%Length, ep%YoungE, ep%T0, eP%DirCos, Ke)

   else if (ep%eType==idMemberRigid) then
      Ke = 0.0_ReKi
   endif
END SUBROUTINE ElemK

SUBROUTINE ElemF(ep, gravity, Fg, Fo)
   TYPE(ElemPropType), INTENT(IN) :: eP        !< Element Property
   REAL(ReKi), INTENT(IN)     :: gravity       !< acceleration of gravity
   REAL(ReKi), INTENT(OUT)    :: Fg(12)
   REAL(ReKi), INTENT(OUT)    :: Fo(12)
   if (ep%eType==idMemberBeam) then
      Fo(1:12)=0
   else if (ep%eType==idMemberCable) then
      CALL ElemF_Cable(ep%T0, ep%DirCos, Fo)
   else if (ep%eType==idMemberRigid) then
      Fo(1:12)=0
   endif
   CALL ElemG( eP%Area, eP%Length, eP%rho, eP%DirCos, Fg, gravity )
END SUBROUTINE ElemF

END MODULE SD_FEM
