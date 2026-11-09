> **Nota:** estas son las notas de diseño iniciales (en español), escritas cuando AgentWorld era solo una interfaz para Claude Code. La app ya soporta varios CLIs de agentes; el estado actual está en el [README](../README.md) y en la [hoja de ruta](../Sidebar/ROADMAP.md).

# AgentWorld --- Concepto, arquitectura y plan de desarrollo

## 1. Idea general

**AgentWorld** es una aplicación nativa para macOS pensada como una
**interfaz visual para Claude Code**.

La idea no es sustituir Claude Code ni crear otro agente de
programación. Tampoco queremos construir otro terminal o una simple
interfaz de chat.

El objetivo es hacer visible y comprensible todo el ecosistema que
existe alrededor de un proyecto de Claude Code:

-   Agents
-   Skills
-   Tools
-   MCP
-   Hooks
-   Permissions
-   Sessions
-   Tasks
-   Subagents
-   Configuración del proyecto

La aplicación debe funcionar como una especie de **capa visual /
harness** sobre Claude Code.

Una buena analogía es:

> Finder hace que trabajar con archivos sea más comprensible sin
> obligarte a pensar constantemente en el sistema de archivos.

AgentWorld debería hacer algo parecido con Claude Code y su
configuración.

------------------------------------------------------------------------

# 2. Qué problema queremos solucionar

Claude Code es muy potente, pero gran parte de su configuración y
funcionamiento se encuentra repartida entre archivos y conceptos que
pueden resultar poco intuitivos:

``` text
.claude/
├── agents/
├── skills/
├── ...
```

Para alguien que empieza puede ser difícil entender:

-   qué agentes existen;
-   qué hace cada agente;
-   qué skills tiene;
-   qué herramientas puede utilizar;
-   qué MCP tiene configurado;
-   qué permisos tiene;
-   qué hooks existen;
-   qué está haciendo Claude en cada momento;
-   cómo se relacionan unos agentes con otros.

AgentWorld quiere convertir ese sistema en algo que se pueda **ver,
explorar y gestionar visualmente**.

------------------------------------------------------------------------

# 3. Concepto visual

La aplicación utiliza personajes animados para representar a los
agentes.

El personaje no es solamente decoración.

Es una representación visual del estado real del agente.

Por ejemplo:

``` text
IDLE       → personaje esperando
THINKING   → personaje pensando
READING    → leyendo archivos
WORKING    → trabajando / programando
WAITING    → esperando
SUCCESS    → trabajo terminado correctamente
ERROR      → error
```

Cuando Claude Code utiliza una herramienta, el personaje puede
reaccionar.

Ejemplo:

``` text
Claude llama a Read
        ↓
AgentWorld recibe el evento
        ↓
Personaje cambia a "reading"
        ↓
Se muestra el archivo que está leyendo
```

O:

``` text
Claude llama a Edit
        ↓
Personaje cambia a "working"
        ↓
Se muestra la acción
```

La finalidad es que mirando la aplicación podamos entender rápidamente:

> "¿Qué está haciendo ahora mismo Claude?"

------------------------------------------------------------------------

# 4. Metáfora principal

La interfaz puede traducir conceptos técnicos de Claude Code a conceptos
visuales:

  Claude Code   AgentWorld
  ------------- ----------------------------
  Agent         Personaje / trabajador
  Skill         Habilidad
  Tool          Herramienta / equipamiento
  MCP           Conexión
  Permission    Acceso
  Hook          Disparador
  Session       Misión
  Task          Quest / tarea
  Subagent      Compañero
  Project       Mundo / espacio de trabajo

Importante:

> La interfaz debe traducir Claude Code, no esconder Claude Code.

Los usuarios avanzados deben poder seguir viendo la información técnica
real cuando quieran.

------------------------------------------------------------------------

# 5. Público objetivo

Queremos que funcione tanto para:

### Usuarios principiantes

Que puedan crear y configurar agentes sin tener que conocer de memoria
toda la estructura de `.claude`.

Por ejemplo:

``` text
Crear agente

Nombre:
Descripción:
Modelo:
Skills:
Herramientas:
Permisos:
```

La aplicación se encarga de generar la configuración correspondiente.

### Usuarios avanzados

Que puedan:

-   inspeccionar configuraciones;
-   ver rápidamente todos los agentes;
-   editar configuraciones;
-   visualizar actividad;
-   comprobar herramientas;
-   inspeccionar eventos;
-   ver la relación entre agentes;
-   acceder a los datos técnicos originales.

------------------------------------------------------------------------

# 6. La aplicación NO será

## No será otro terminal

No queremos sustituir:

-   Warp
-   Terminal.app
-   iTerm2
-   terminal de VS Code
-   otros terminales

AgentWorld debe ser **terminal-agnóstico**.

La arquitectura conceptual es:

``` text
macOS
│
├── Warp
│
├── Terminal.app
│
├── iTerm2
│
└── AgentWorld
        │
        └── Claude Code
```

Warp es simplemente el terminal que utilizamos actualmente. AgentWorld
no debe depender de Warp.

Inicialmente AgentWorld puede lanzar su propio proceso de Claude Code
mediante un subprocess, pero no necesita implementar un terminal/PTY.

En una fase posterior se podría estudiar la observación de sesiones de
Claude Code lanzadas externamente.

------------------------------------------------------------------------

# 7. Arquitectura general

La arquitectura propuesta es:

``` text
SwiftUI UI
    ↓
Application Core
    ↓
ProjectManager / AgentManager
    ↓
.claude
    ↓
ClaudeRuntime
    ↓
Claude Code CLI
    ↓
stream-json
    ↓
Event Parser
    ↓
EventBus
    ↓
Application State
    ↓
SwiftUI
```

La aplicación debe estar desacoplada de Claude Code todo lo posible.

Aunque el MVP utilizará Claude Code, internamente queremos pensar en un
runtime genérico:

``` text
AgentRuntime
    │
    ├── ClaudeCodeRuntime
    │
    ├── CodexRuntime       (futuro)
    │
    └── GeminiRuntime      (futuro)
```

No hace falta implementar esos runtimes ahora.

------------------------------------------------------------------------

# 8. Arquitectura interna

Propuesta:

``` text
AgentWorld/
├── App/
│   └── AgentWorldApp.swift
│
├── Core/
│   ├── Agent/
│   │   ├── Agent.swift
│   │   └── AgentManager.swift
│   │
│   ├── Skill/
│   │   ├── Skill.swift
│   │   └── SkillManager.swift
│   │
│   ├── Tool/
│   │   └── Tool.swift
│   │
│   ├── Project/
│   │   ├── Project.swift
│   │   └── ProjectManager.swift
│   │
│   └── Events/
│       ├── AgentEvent.swift
│       └── EventBus.swift
│
├── Claude/
│   ├── ClaudeRuntime.swift
│   ├── ClaudeProcess.swift
│   └── ClaudeEventParser.swift
│
├── UI/
│   ├── Dashboard/
│   ├── Agents/
│   ├── Skills/
│   └── Characters/
│
└── Resources/
    └── Characters/
```

------------------------------------------------------------------------

# 9. Modelo de datos

El modelo interno no debe ser una copia exacta de los archivos de Claude
Code.

Debe representar lo que necesita la aplicación.

Ejemplo:

``` swift
struct Agent: Identifiable {
    let id: UUID
    var name: String
    var description: String
    var skills: [Skill]
    var tools: [Tool]
    var status: AgentStatus
}

enum AgentStatus {
    case idle
    case thinking
    case working
    case waiting
    case completed
    case error
}
```

La idea es tener un parser/adaptador que traduzca:

``` text
Claude Code configuration
        ↓
ClaudeConfigParser
        ↓
AgentWorld internal model
        ↓
SwiftUI
```

------------------------------------------------------------------------

# 10. Eventos

Para que los personajes puedan reaccionar necesitamos un sistema de
eventos interno.

Eventos previstos:

``` text
AgentStarted
AgentThinking
ToolStarted
ToolFinished
MessageReceived
FileChanged
CommandExecuted
AgentFinished
AgentError
```

Por ejemplo:

``` text
ToolStarted(Read)
        ↓
AgentEvent
        ↓
EventBus
        ↓
Application State
        ↓
Character = READING
```

Esto permitirá que la interfaz reaccione al comportamiento real de
Claude Code.

------------------------------------------------------------------------

# 11. Claude Code y stream-json

Una de las partes importantes de la integración será ejecutar Claude
Code mediante:

``` text
claude -p --output-format stream-json
```

La aplicación leerá continuamente la salida JSON del proceso.

Conceptualmente:

``` text
Claude Code
    │
    │ stdout
    ▼
stream-json
    │
    ▼
ClaudeEventParser
    │
    ▼
AgentEvent
    │
    ▼
EventBus
    │
    ▼
SwiftUI
```

Antes de implementar el parser definitivo hay que comprobar la
documentación y los esquemas actuales de Claude Code, porque estos
detalles pueden cambiar.

------------------------------------------------------------------------

# 12. Proyecto y carpeta .claude

El primer objetivo real del proyecto es extremadamente sencillo:

> Abrir un proyecto y descubrir qué configuración de Claude Code tiene.

El usuario seleccionará una carpeta:

``` text
MiProyecto/
├── .claude/
│   ├── agents/
│   ├── skills/
│   └── ...
├── src/
└── ...
```

AgentWorld deberá detectar:

``` text
.claude
```

y posteriormente descubrir:

``` text
Agents
Skills
Tools
MCP
Hooks
Permissions
...
```

------------------------------------------------------------------------

# 13. Primer MVP

No debemos intentar construir todo desde el principio.

El MVP se plantea en fases:

### Fase 1 --- Project Explorer

-   Abrir una carpeta.
-   Detectar `.claude`.
-   Leer agentes.
-   Leer skills.
-   Identificar herramientas/configuración relevante.
-   Mostrarlo en una interfaz sencilla.

### Fase 2 --- Primer personaje

Representar visualmente un agente.

``` text
Agent
  ↓
Character
```

Todavía sin animaciones complejas.

### Fase 3 --- Conectar Claude Code

Ejecutar Claude Code como subprocess.

Recibir:

``` text
stream-json
```

y convertir los eventos en estados internos.

### Fase 4 --- Personaje reactivo

El personaje cambia según la actividad:

``` text
thinking
reading
working
waiting
success
error
```

### Fase 5 --- Agent Creator

Crear agentes desde una interfaz gráfica.

### Fase 6 --- Skill Creator

Crear y gestionar skills.

### Fase 7 --- Tools / MCP

Mostrar y gestionar herramientas y conexiones.

### Fase 8 --- Sessions / Activity

Mostrar:

-   sesiones;
-   historial;
-   actividad;
-   herramientas utilizadas;
-   archivos modificados;
-   comandos ejecutados.

### Fase 9 --- Multi-agent

Visualizar relaciones como:

``` text
          Coder
         /     \
        ↓       ↓
 Researcher   Tester
```

Incluso mostrando visualmente la delegación.

### Fase 10 --- Harness

Funciones avanzadas:

-   hooks;
-   permisos;
-   worktrees;
-   contexto;
-   memoria;
-   configuración avanzada.

------------------------------------------------------------------------

# 14. Primera interfaz prevista

Una posible interfaz principal:

``` text
┌─────────────────────────────────────────────┐
│ AgentWorld                                  │
├───────────────┬─────────────────────────────┤
│ PROJECT       │                             │
│               │        AGENTS               │
│ Agents        │                             │
│ Skills        │     🧑‍💻     🧑‍🔬             │
│ Tools         │                             │
│ MCP           │   Coder    Researcher       │
│ Sessions      │                             │
│               │        🧪                    │
│               │       Tester                │
├───────────────┴─────────────────────────────┤
│ Activity                                    │
│ Read main.swift                             │
│ Edit Agent.swift                            │
│ Bash git status                             │
└─────────────────────────────────────────────┘
```

Otra vista podría ser un mapa completo del proyecto:

``` text
PROJECT
│
├── AGENTS
│   ├── Coder
│   ├── Researcher
│   └── Tester
│
├── SKILLS
│   ├── SwiftUI
│   ├── Git
│   └── Testing
│
├── TOOLS
│   ├── Read
│   ├── Edit
│   └── Bash
│
└── MCP
    ├── GitHub
    └── Database
```

------------------------------------------------------------------------

# 15. Agent Inspector

Al seleccionar un agente:

``` text
Coder

Status
● Working

Model
...

Description
...

Skills
✓ SwiftUI
✓ Git
✓ Testing

Tools
✓ Read
✓ Edit
✓ Bash

Permissions
...

Current action
Editing AgentManager.swift
```

El usuario avanzado puede acceder además a la configuración técnica
real.

------------------------------------------------------------------------

# 16. Creación de agentes

Queremos dos niveles.

### Simple

``` text
Create Agent

Name:
Description:
Role:
Model:

[ Create ]
```

### Advanced

``` text
Create Agent

Name
Description
Model
Skills
Tools
Permissions
Hooks
Advanced configuration
```

La aplicación debe escribir la configuración real que Claude Code
necesita.

La UI es una capa visual, no un sistema paralelo.

------------------------------------------------------------------------

# 17. Cambios externos

Un requisito importante a largo plazo es que AgentWorld no se convierta
en la única forma de editar la configuración.

Si el usuario cambia algo desde Warp o desde un editor:

``` text
Warp / VS Code / Finder
        ↓
.claude
        ↓
FileSystem watcher
        ↓
AgentWorld
        ↓
UI actualizada
```

Por tanto, si alguien modifica un agent manualmente, AgentWorld debería
detectar el cambio y reflejarlo.

------------------------------------------------------------------------

# 18. Principios de diseño

## 1. Claude Code sigue siendo el motor

AgentWorld no reemplaza el agente.

## 2. No esconder la complejidad

La aplicación debe hacerla comprensible.

## 3. Visual primero

El estado debe poder entenderse de un vistazo.

## 4. Configuración real

No crear una configuración ficticia que solo funcione dentro de
AgentWorld.

## 5. Terminal-agnóstico

No depender de Warp.

## 6. Runtime desacoplado

Claude Code inicialmente, pero arquitectura preparada para otros
runtimes.

## 7. Avanzado y sencillo

Una interfaz fácil para principiantes y acceso técnico para usuarios
avanzados.

## 8. Los personajes tienen significado

Las animaciones representan estados y eventos reales.

------------------------------------------------------------------------

# 19. Tecnología

La aplicación será inicialmente:

``` text
macOS
Swift
SwiftUI
Xcode
```

Motivos:

-   integración nativa con macOS;
-   ventanas flotantes;
-   transparencia;
-   animaciones;
-   filesystem;
-   notificaciones;
-   procesos/subprocess;
-   Swift Concurrency;
-   buena integración con el sistema.

No vamos a crear un terminal nuevo.

------------------------------------------------------------------------

# 20. Estado actual del proyecto

El proyecto Xcode ya está creado.

Ruta:

``` text
/Users/rogergongas/Developer/AgentWorld
```

Configuración:

``` text
macOS App
SwiftUI
Swift
```

El siguiente paso es construir el primer `ProjectManager`.

------------------------------------------------------------------------

# 21. Código inicial actual

## Project.swift

``` swift
import Foundation

struct Project: Identifiable {
    let id = UUID()
    let name: String
    let path: URL
    let hasClaudeDirectory: Bool
}
```

## ProjectManager.swift

``` swift
import Foundation

@MainActor
final class ProjectManager: ObservableObject {

    @Published var project: Project?

    func openProject() {
        let panel = NSOpenPanel()

        panel.title = "Selecciona un proyecto"
        panel.message = "Selecciona la carpeta raíz de tu proyecto"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK,
           let url = panel.url {

            let claudeDirectory = url.appendingPathComponent(".claude")

            let hasClaudeDirectory = FileManager.default.fileExists(
                atPath: claudeDirectory.path
            )

            project = Project(
                name: url.lastPathComponent,
                path: url,
                hasClaudeDirectory: hasClaudeDirectory
            )
        }
    }
}
```

## ContentView.swift

``` swift
import SwiftUI

struct ContentView: View {

    @StateObject private var projectManager = ProjectManager()

    var body: some View {
        VStack(spacing: 20) {

            Text("AgentWorld")
                .font(.largeTitle)
                .fontWeight(.bold)

            if let project = projectManager.project {

                VStack(spacing: 10) {
                    Text(project.name)
                        .font(.title2)

                    Text(project.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if project.hasClaudeDirectory {
                        Label(
                            "Claude Code detectado",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    } else {
                        Label(
                            "No se encontró .claude",
                            systemImage: "xmark.circle.fill"
                        )
                        .foregroundStyle(.red)
                    }
                }

            } else {

                Text("Ningún proyecto seleccionado")
                    .foregroundStyle(.secondary)

                Button("Abrir proyecto") {
                    projectManager.openProject()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
```

------------------------------------------------------------------------

# 22. Primer objetivo inmediato

La primera versión funcional debe hacer exactamente esto:

``` text
AgentWorld
    ↓
Abrir proyecto
    ↓
Seleccionar carpeta
    ↓
Buscar .claude
    ↓
Mostrar:
    ✓ Claude Code detectado
    o
    ✗ No encontrado
```

Una vez esto funcione, el siguiente paso será:

``` text
.claude
   ├── agents
   │    ├── ...
   │    └── ...
   │
   └── skills
        ├── ...
        └── ...
```

y convertir esos archivos reales en:

``` text
Project
 ├── Agents
 │    ├── Agent
 │    └── Agent
 │
 └── Skills
      ├── Skill
      └── Skill
```

Después podremos empezar a visualizar esos agentes.

------------------------------------------------------------------------

# 23. Orden de desarrollo recomendado

``` text
[1] Crear proyecto Xcode
        ↓
[2] ProjectManager
        ↓
[3] Detectar .claude
        ↓
[4] Leer Agents
        ↓
[5] Leer Skills
        ↓
[6] Modelo interno
        ↓
[7] Dashboard visual
        ↓
[8] Primer personaje
        ↓
[9] ClaudeRuntime
        ↓
[10] stream-json
        ↓
[11] EventBus
        ↓
[12] Personaje reactivo
        ↓
[13] Agent Creator
        ↓
[14] Skill Creator
        ↓
[15] Tools / MCP
        ↓
[16] Sessions
        ↓
[17] Multi-agent
        ↓
[18] Harness avanzado
```

------------------------------------------------------------------------

# 24. Regla para el desarrollo

No intentar construir todo de golpe.

Cada paso debe dejar la aplicación funcionando.

La estrategia será:

> construir → ejecutar → comprobar → añadir una capa → volver a
> ejecutar.

Así evitamos terminar con una arquitectura enorme que no sabemos si
realmente funciona.

------------------------------------------------------------------------

# 25. Visión final

La visión de AgentWorld es que al abrir un proyecto no tengas que
pensar:

> "¿Dónde está este agent? ¿Qué skill utiliza? ¿Qué tools tiene? ¿Qué
> MCP está conectado? ¿Qué está haciendo Claude?"

Sino que puedas abrir AgentWorld y verlo:

``` text
                  AGENTWORLD

        ┌─────────────────────────┐
        │       MY PROJECT        │
        │                         │
        │   🧑‍💻 Coder             │
        │      │                  │
        │      ├── SwiftUI       │
        │      ├── Git           │
        │      └── Edit          │
        │           │             │
        │           ▼             │
        │      🧪 Tester          │
        │                         │
        │   🧑‍🔬 Researcher       │
        │                         │
        └─────────────────────────┘

             ● Coder working

        Editing ProjectManager.swift
```

Y que, sin dejar de utilizar Claude Code como motor, la persona pueda
entender visualmente qué está ocurriendo.

**Ese es el objetivo de AgentWorld.**
