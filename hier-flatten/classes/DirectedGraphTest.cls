/*
 * Mike Ulveling
 */
@isTest
private class DirectedGraphTest {
    
    @IsTest
    static void buildPathsByCodes() {
        Harness testSet = new Harness();
        
        DirectedGraph graph = new DirectedGraph.Builder(Schema.Hierarchy_Test__c.sObjectType, 'rkcore__Code__c', 'rkcore__Parent_Code__c')
            .toGraph(new sObject[]{ 
                    testSet.n('01'),
                    testSet.n('04'),
                    testSet.n('06'),
                    testSet.n('07'), 
                    testSet.n('08'),
                    testSet.n('09'),
                    testSet.n('20'),
                    testSet.n('A'),
                    testSet.n('I')  
                }, 1);

        Map<Id, DirectedGraph.Path> paths = graph.getStartPaths();
        final String sep = ' 🡒 ';
        DirectedGraph.Path p = paths.get(testSet.n('01').Id);
        Assert.areEqual('01 🡒 A 🡒 I 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('04').Id);
        Assert.areEqual('04 🡒 C 🡒 II 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('06').Id);
        Assert.areEqual('06 🡒 C 🡒 II 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('07').Id);
        Assert.areEqual('07 🡒 D 🡒 III 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('08').Id);
        Assert.areEqual('08 🡒 E 🡒 III 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('09').Id);
        Assert.areEqual('09 🡒 E 🡒 III 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('20').Id);
        Assert.areEqual('20 🡒 F 🡒 III 🡒 R', p.ser(sep));

        p = paths.get(testSet.n('I').Id);
        Assert.areEqual('I 🡒 R', p.ser(sep));
        p = paths.get(testSet.n('A').Id);
        Assert.areEqual('A 🡒 I 🡒 R', p.ser(sep));
    }

    @isTest
    static void testCycleDetection() {
        Harness testSet = new Harness();
        // Root now points to a leaf node!
        Hierarchy_Test__c root = testSet.n('R');
        root.Parent_Code__c = '20';
        update root;
        
        DirectedGraph graph = new DirectedGraph.Builder(Schema.Hierarchy_Test__c.sObjectType, 'rkcore__Code__c', 'rkcore__Parent_Code__c')
            .toGraph(new sObject[]{ 
                    testSet.n('01'),
                    testSet.n('04'),
                    testSet.n('06'),
                    testSet.n('07'), 
                    testSet.n('08'),
                    testSet.n('09'),
                    testSet.n('20'),
                    testSet.n('A'),
                    testSet.n('I')  
                }, 1);

        Map<Id, DirectedGraph.Path> paths = graph.getStartPaths();
        final String sep = ' 🡒 ';
        DirectedGraph.Path p = paths.get(testSet.n('01').Id);
        Assert.areEqual('01 🡒 A 🡒 I 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('04').Id);
        Assert.areEqual('04 🡒 C 🡒 II 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('06').Id);
        Assert.areEqual('06 🡒 C 🡒 II 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('07').Id);
        Assert.areEqual('07 🡒 D 🡒 III 🡒 R 🡒 20 🡒 F 🡒 III 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('08').Id);
        Assert.areEqual('08 🡒 E 🡒 III 🡒 R 🡒 20 🡒 F 🡒 III 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('09').Id);
        Assert.areEqual('09 🡒 E 🡒 III 🡒 R 🡒 20 🡒 F 🡒 III 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('20').Id);
        Assert.areEqual('20 🡒 F 🡒 III 🡒 R 🡒 20 🡒 {cyclic}', p.ser(sep));

        p = paths.get(testSet.n('I').Id);
        Assert.areEqual('I 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));
        p = paths.get(testSet.n('A').Id);
        Assert.areEqual('A 🡒 I 🡒 R 🡒 20 🡒 F 🡒 III 🡒 R 🡒 {cyclic}', p.ser(sep));
    }

    @IsTest
    static void buildPathsByLkp() {
        Harness testSet = new Harness();

        Map<Id, Hierarchy_Test__c> hiersMap = new Map<Id, Hierarchy_Test__c>([ SELECT Code__c, Parent_Code__c FROM Hierarchy_Test__c ]);
        DirectedGraph graph = new DirectedGraph.Builder(Schema.Hierarchy_Test__c.sObjectType, 'rkcore__Code__c', 'rkcore__Parent_Code__c')
            .toGraph(hiersMap.values(), 1);
        
        Map<Id, DirectedGraph.Path> pathsMap = graph.getStartPaths();
        for (Id nodeId : pathsMap.keySet()) {
            DirectedGraph.Path path = pathsMap.get(nodeId);
            // A path's "start" is the Node corresponding to the nodeId (Hierarchy_Test__c.Id) it was mapped under:
            DirectedGraph.Node start = path.start;
            DirectedGraph.Node parent = start.next;
            if (parent != null) {
                Hierarchy_Test__c nodeData = hiersMap.get(nodeId);
                nodeData.Parent__c = parent.data.Id;
                if (!path.cyclic) {
                    Integer level = path.acyclicLength;
                    nodeData.Level__c = level;
                    for (; --level >= 1;) {
                        nodeData.put('Parent_Level_' + level + '__c', parent.data.Id);
                        parent = parent.next;
                    }
                }
            }
        }
        update hiersMap.values();
        
        graph = new DirectedGraph.Builder(Schema.Hierarchy_Test__c.sObjectType, 'rkcore__Parent__c')
            .addSelects(new String[]{ 
                    'rkcore__Parent_Code__c', 'rkcore__Level__c', 'rkcore__Parent_Level_1__c', 'rkcore__Parent_Level_2__c', 
                    'rkcore__Parent_Level_3__c', 'rkcore__Parent_Level_4__c', 'rkcore__Parent_Level_5__c' })
                .toGraph(hiersMap.keySet());
        pathsMap = graph.getStartPaths();

        DirectedGraph.Path p = pathsMap.get(testSet.n('07').Id);
        Hierarchy_Test__c pData = (Hierarchy_Test__c) p.start.data;

        Assert.areEqual(4, pData.Level__c);
        Assert.areEqual(testSet.n('D').Id, pData.Parent__c);
        Assert.areEqual(testSet.n('R').Id, pData.Parent_Level_1__c);
        Assert.areEqual(testSet.n('III').Id, pData.Parent_Level_2__c);
        Assert.areEqual(testSet.n('D').Id, pData.Parent_Level_3__c);
        Assert.isNull(pData.Parent_Level_4__c);

        Assert.areEqual(1, graph.queryCount);
    }

    @IsTest
    static void testHierFlattenInMemory() {
        Harness harness = new Harness();

        HierFlatten flatten = HierFlatten.TargetSelf(Schema.Hierarchy_Test__c.sObjectType, 'rkcore__Code__c', 'rkcore__Parent_Code__c')
            .fillSelfLookup('rkcore__Parent__c')
            .fillLevelNumber('rkcore__Level__c')
            .fillAncestorLookupsFrom(8, 'rkcore__Parent_Level_{0}__c');
        
        // Here we'll query the entire hierarchy node set into our starting set, so HierAncestry 
        // explore it all "in memory" via a single degree/query pass:
        flatten.go2(SOQLContext.newSystemMode().query('SELECT * FROM rkcore__Hierarchy_Test__c'));
        harness.load();

        Hierarchy_Test__c n_07 = harness.n('07');
        Assert.areEqual(4, n_07.Level__c);
        Assert.areEqual(harness.n('D').Id, n_07.Parent__c);
        Assert.areEqual(harness.n('R').Id, n_07.Parent_Level_1__c);
        Assert.areEqual(harness.n('III').Id, n_07.Parent_Level_2__c);
        Assert.areEqual(harness.n('D').Id, n_07.Parent_Level_3__c);
        Assert.isNull(n_07.Parent_Level_4__c);
    }

    @IsTest
    static void testHierFlattenFromLeaves() {
        Harness harness = new Harness();

        HierFlatten flatten = HierFlatten.TargetSelf(Schema.Hierarchy_Test__c.sObjectType, 'rkcore__Code__c', 'rkcore__Parent_Code__c')
            .fillSelfLookup('rkcore__Parent__c')
            .fillLevelNumber('rkcore__Level__c')
            .fillAncestorLookupsFrom(8, 'rkcore__Parent_Level_{0}__c');
        
        // Here we'll query the ONLY leaf nodes into our starting set, so HierAncestry will 
        // explore the hierarchy via multiple degrees/query passes:
        String[] leafNodeCodes = new String[0];
        for (Integer i = 1; i <= 20; i++) {
            leafNodeCodes.add(String.valueOf(i).leftPad(2, '0'));
        }
        flatten.go2(SOQLContext.newSystemMode().query(
            'SELECT *' + 
            ' FROM rkcore__Hierarchy_Test__c' + 
            ' WHERE rkcore__Code__c IN ("' + String.join(leafNodeCodes, '","') + '")'));
        harness.load();

        Hierarchy_Test__c n_07 = harness.n('07');
        Assert.areEqual(4, n_07.Level__c);
        Assert.areEqual(harness.n('D').Id, n_07.Parent__c);
        Assert.areEqual(harness.n('R').Id, n_07.Parent_Level_1__c);
        Assert.areEqual(harness.n('III').Id, n_07.Parent_Level_2__c);
        Assert.areEqual(harness.n('D').Id, n_07.Parent_Level_3__c);
        Assert.isNull(n_07.Parent_Level_4__c);
    }

    // TODO: Test HierFlatten when targeting a child object...
    // TODO: Test self-level writing when that scenario is allowed (no CIRCULAR_REFERENCE)...

    class Harness {
        Hierarchy_Test__c[] newNodes;
        Map<String, Hierarchy_Test__c> nodesByCode = new Map<String, Hierarchy_Test__c>();

        Harness() {
            init();
        }

        Harness load() {
            this.loadHiers();
            return this;
        }

        Harness loadHiers() {
            this.nodesByCode = new Map<String, Hierarchy_Test__c>();
            for (Hierarchy_Test__c hier : (Hierarchy_Test__c[]) SOQLContext.newSystemMode()
                    .query('SELECT * FROM rkcore__Hierarchy_Test__c')) {
                nodesByCode.put(hier.Code__c, hier);
            }
            return this;
        }

        Harness init() {
            initHiers();
            return this;
        }

        Hierarchy_Test__c n(String code) {
            Hierarchy_Test__c node = this.nodesByCode.get(code);
            if (node == null) {
                Assert.fail(String.format('Node [{0}] does not exist', new String[]{ code }));
            }
            return node;
        }

        void initHiers() {
            nn('R', null);
            saveHiers();
            nn('I', 'R');
            nn('II', 'R');
            nn('III', 'R');
            saveHiers();
            nn('A', 'I');
            nn('B', 'I');
            nn('C', 'II');
            
            nn('D', 'III');
            //nn('D', 'iii'); // test caseInsensitive()

            nn('E', 'III');
            nn('F', 'III');
            saveHiers();
            nn('01', 'A');
            nn('02', 'A');
            nn('03', 'B');
            nn('04', 'C');
            nn('05', 'C');
            nn('06', 'C');
            nn('07', 'D');
            nn('08', 'E');
            nn('09', 'E');
            nn('10', 'F');
            nn('11', 'F');
            nn('12', 'F');
            nn('13', 'F');
            nn('14', 'F');
            nn('15', 'F');
            nn('16', 'F');
            nn('17', 'F');
            nn('18', 'F');
            nn('19', 'F');
            nn('20', 'F');
            saveHiers();
        }

        // nn stands for "new node":
        Hierarchy_Test__c nn(String code, String parentCode) {
            return nn(code, parentCode, false);
        }

        // nn stands for "new node":
        Hierarchy_Test__c nn(String code, String parentCode, Boolean resolveParent) {
            if (this.newNodes == null) {
                this.newNodes = new Hierarchy_Test__c[]{};
            }
            Hierarchy_Test__c newNode = new Hierarchy_Test__c(Name = code, Code__c = code, Parent_Code__c = parentCode);
            this.newNodes.add(newNode);
            Hierarchy_Test__c clash = this.nodesByCode.put(code, newNode);
            if (clash != null) {
                Assert.fail(String.format('Node with code [{0}] was previously created)', new String[]{ code }));
            }
            // try to resolve the parent, if this was flagged:
            if (resolveParent == true && parentCode != null) {
                Hierarchy_Test__c parentNode = this.nodesByCode.get(parentCode);
                if (parentNode == null) {
                    Assert.fail(String.format(
                        'Node [{0}] cannot resolve parent node [{1}]', new String[]{ code, parentCode }));
                }
                if (parentNode.Id == null) {
                    Assert.fail(String.format(
                        'Node [{0}] cannot resolve parent node [{1}] before the latter has been inserted', new String[]{ code, parentCode }));
                }
                newNode.Parent__c = parentNode.Id;
            }
            return newNode;
        }

        void saveHiers() {
            if (this.newNodes != null) {
                insert this.newNodes;
                this.newNodes = null;
            }
        }
        
    }
}