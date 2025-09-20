const { Server } = require("@modelcontextprotocol/sdk/server/index.js");
const { StdioServerTransport } = require("@modelcontextprotocol/sdk/server/stdio.js");
const { CallToolRequestSchema, ListToolsRequestSchema } = require("@modelcontextprotocol/sdk/types.js");
const { z } = require("zod");
const axios = require("axios");
const dotenv = require("dotenv");

dotenv.config();

// Esquemas de validação com Zod
const schemas = {
  toolInputs: {
    enviaMensagem: z.object({
      number: z.string(),
      mensagem: z.string(),
    }),
    criaGrupo: z.object({
      subject: z.string(),
      description: z.string().optional(),
      participants: z.array(z.string()),
    }),
    buscaGrupos: z.object({
      getParticipants: z.boolean().optional().default(false),
    }),
    buscaParticipantesGrupo: z.object({
      groupJid: z.string(),
    }),
  },
};

// Definições das ferramentas (tools)
const TOOL_DEFINITIONS = [
  {
    name: "envia_mensagem",
    description: "Envia mensagem de texto via API Evolution",
    inputSchema: {
      type: "object",
      properties: {
        number: { type: "string", description: "Número do destinatário com DDI e DDD" },
        mensagem: { type: "string", description: "Texto da mensagem a ser enviada" },
      },
      required: ["number", "mensagem"],
    },
  },
  {
    name: "cria_grupo",
    description: "Cria um grupo via API Evolution",
    inputSchema: {
      type: "object",
      properties: {
        subject: { type: "string", description: "Nome do grupo" },
        description: { type: "string", description: "Descrição do grupo" },
        participants: {
          type: "array",
          items: { type: "string" },
          description: "Participantes do grupo (números com DDI/DDD)"
        },
      },
      required: ["subject", "participants"],
    },
  },
  {
    name: "busca_grupos",
    description: "Busca todos os grupos da instância com opção de listar participantes.",
    inputSchema: {
      type: "object",
      properties: {
        getParticipants: {
          type: "boolean",
          description: "Listar participantes dos grupos?",
          default: false,
        },
      },
      required: [],
    },
  },
  {
    name: "busca_participantes_grupo",
    description: "Busca participantes específicos de um grupo pela instância.",
    inputSchema: {
      type: "object",
      properties: {
        groupJid: { type: "string", description: "Identificador do grupo" },
      },
      required: ["groupJid"],
    },
  },
];

// Handlers das ferramentas
const toolHandlers = {
  envia_mensagem: async (args) => {
    const parsed = schemas.toolInputs.enviaMensagem.parse(args);

    const instancia = process.env.EVOLUTION_INSTANCIA;
    const apikey = process.env.EVOLUTION_APIKEY;
    const apiBase = process.env.EVOLUTION_API_BASE || "sua_url_evolution";

    const url = `http://${apiBase}/message/sendText/${instancia}`;
    const response = await axios.post(url, {
      number: parsed.number,
      text: parsed.mensagem,
    }, {
      headers: {
        "Content-Type": "application/json",
        "apikey": apikey,
      },
    });

    return {
      content: [{
        type: "text",
        text: `Mensagem enviada com sucesso para ${parsed.number}.\nResposta: ${JSON.stringify(response.data)}`,
      }],
    };
  },

  cria_grupo: async (args) => {
    const parsed = schemas.toolInputs.criaGrupo.parse(args);

    const instancia = process.env.EVOLUTION_INSTANCIA;
    const apikey = process.env.EVOLUTION_APIKEY;
    const apiBase = process.env.EVOLUTION_API_BASE || "url_evolution";

    const url = `http://${apiBase}/group/create/${instancia}`;
    const response = await axios.post(url, {
      subject: parsed.subject,
      description: parsed.description,
      participants: parsed.participants,
    }, {
      headers: {
        "Content-Type": "application/json",
        "apikey": apikey,
      },
    });

    return {
      content: [{
        type: "text",
        text: `Grupo criado com sucesso!\nResposta: ${JSON.stringify(response.data)}`,
      }],
    };
  },

  busca_grupos: async (args) => {
    const parsed = schemas.toolInputs.buscaGrupos.parse(args);

    const instancia = process.env.EVOLUTION_INSTANCIA;
    const apikey = process.env.EVOLUTION_APIKEY;
    const apiBase = process.env.EVOLUTION_API_BASE || "url_evolution";

    const url = `http://${apiBase}/group/fetchAllGroups/${instancia}?getParticipants=${parsed.getParticipants}`;

    try {
      const response = await axios.get(url, {
        headers: {
          "Content-Type": "application/json",
          "apikey": apikey,
        },
      });

      return {
        content: [{
          type: "text",
          text: `Grupos obtidos com sucesso:\n${JSON.stringify(response.data, null, 2)}`,
        }],
      };
    } catch (error) {
      console.error("Erro na chamada API Evolution:", error);
      return {
        content: [{
          type: "text",
          text: `Erro ao obter grupos: ${error.message}`,
        }],
      };
    }
  },

  busca_participantes_grupo: async (args) => {
    const parsed = schemas.toolInputs.buscaParticipantesGrupo.parse(args);

    const instancia = process.env.EVOLUTION_INSTANCIA;
    const apikey = process.env.EVOLUTION_APIKEY;
    const apiBase = process.env.EVOLUTION_API_BASE || "url_evolution";

    const url = `http://${apiBase}/group/participants/${instancia}?groupJid=${parsed.groupJid}`;

    try {
      const response = await axios.get(url, {
        headers: {
          "Content-Type": "application/json",
          "apikey": apikey,
        },
      });

      return {
        content: [{
          type: "text",
          text: `Participantes obtidos com sucesso:\n${JSON.stringify(response.data, null, 2)}`,
        }],
      };
    } catch (error) {
      console.error("Erro na chamada API Evolution:", error);
      return {
        content: [{
          type: "text",
          text: `Erro ao obter participantes: ${error.message}`,
        }],
      };
    }
  },
};

// Instância do servidor MPC
const server = new Server(
  { name: "evolution-tools-server", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

// Handlers das requisições MPC
server.setRequestHandler(ListToolsRequestSchema, async () => {
  console.error("Ferramenta requesitada pelo cliente");
  return { tools: TOOL_DEFINITIONS };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    const handler = toolHandlers[name];
    if (!handler) throw new Error(`Tool Desconhecida: ${name}`);
    return await handler(args);
  } catch (error) {
    console.error(`Erro executando a tool ${name}:`, error);
    throw error;
  }
});

// Execução principal
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Evolution API MPC Server rodando no stdio");
}

// Execução direta por argumentos CLI
const args = process.argv.slice(2);
if (args.length > 0) {
  const funcao = args[0];
  const input = args[1] ? JSON.parse(args[1]) : {};

  console.log("🔐 Variáveis de ambiente utilizadas:");
  console.log("EVOLUTION_INSTANCIA:", process.env.EVOLUTION_INSTANCIA);
  console.log("EVOLUTION_APIKEY:", process.env.EVOLUTION_APIKEY);
  console.log("EVOLUTION_API_BASE:", process.env.EVOLUTION_API_BASE);

  if (toolHandlers[funcao]) {
    toolHandlers[funcao](input)
      .then((res) => {
        console.log(JSON.stringify(res, null, 2));
        process.exit(0);
      })
      .catch((err) => {
        console.error(`Erro ao executar ${funcao}:`, err);
        process.exit(1);
      });
  } else {
    console.error(`❌ Função desconhecida: ${funcao}`);
    process.exit(1);
  }
} else {
  main().catch((error) => {
    console.error("Erro Fatal:", error);
    process.exit(1);
  });
}